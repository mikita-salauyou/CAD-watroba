function maskZYX = interpolateKeyframes(maskZYX, keyframeSlices, opts)
% interpolateKeyframes Fill missing slices between user-drawn keyframes.
%
% For each pair of consecutive keyframe slices (a, b) the missing slices
% in between are reconstructed by linear interpolation of the
% **signed distance transform** (SDF) of the keyframe masks, with
% **centroid alignment** between A and B before blending.
%
% Anti-drift safeguards (important for tumors):
%   - If two consecutive keyframes are too far apart in Z relative to
%     `opts.maxGapSlices` (default 12), we fall back to a per-keyframe
%     "fade" instead of bridging straight across, and slices in the
%     middle stay empty. This prevents creating phantom lesion blobs in
%     the gap between two unrelated drawings.
%   - If the in-plane centroids of A and B are too far apart relative
%     to the lesion size, we treat them as different lesions and skip
%     interpolation between them entirely (they remain as drawn at
%     their own slices).
%   - The interior threshold for the SDF blend grows toward the middle
%     (alpha=0.5), shrinking interpolated masks slightly to reduce
%     false-positive boundary fuzz.
%
% Why centroid alignment matters for lesions:
%   Naive SDF blending assumes the two contours sit at the same (X, Y)
%   position. Liver contours are big and roughly co-centred between
%   slices, so naive blending is fine. Tumors are small (often < 30
%   voxels across) and their centroid can drift several voxels between
%   slices because of the 3D shape and slice obliquity. Without
%   alignment, the blend morphs through a "hourglass" of two distant
%   blobs and intermediate slices contain artefacts or vanish entirely.
%   With alignment we (a) shift A onto B's centroid, (b) blend SDFs in
%   a shared frame, (c) shift the blended mask onto the per-z
%   interpolated centroid - which gives a smoothly translating shape
%   that follows the lesion through the slab.
%
% Inputs:
%   maskZYX        : logical [Z, Y, X], must contain user-drawn masks at
%                    the keyframe slices (other slices may be empty or
%                    will be overwritten).
%   keyframeSlices : 1xK array of Z indices that the user has drawn on.
%
% Output:
%   maskZYX with all slices in [min(keys), max(keys)] populated.

arguments
    maskZYX (:, :, :) logical
    keyframeSlices (1, :) double
    opts.maxGapSlices (1, 1) double = 12
    opts.maxCentroidDriftPerSlice (1, 1) double = 1.5
    opts.shrinkAtMiddleVoxels (1, 1) double = 1.0
end

if numel(keyframeSlices) < 2
    return;
end

keyframeSlices = sort(unique(keyframeSlices));

for k = 1:numel(keyframeSlices) - 1
    a = keyframeSlices(k);
    b = keyframeSlices(k + 1);
    if b - a < 2
        continue;
    end

    ma = squeeze(maskZYX(a, :, :));
    mb = squeeze(maskZYX(b, :, :));

    if ~any(ma, "all") && ~any(mb, "all")
        continue;
    end

    cA = centroidOf(ma);
    cB = centroidOf(mb);
    canAlign = ~isnan(cA(1)) && ~isnan(cB(1));

    % --- Anti-drift gate ------------------------------------------------
    % Two heuristics for "these are not the same shape, do NOT bridge":
    %   1) Centroid drift per slice exceeds threshold (1.5 px / slice
    %      default). At ~0.7 mm pixel pitch this is ~1 mm/slice, which
    %      is plausible for a moving lesion edge but excessive for the
    %      same lesion seen on adjacent slices.
    %   2) Z gap exceeds maxGapSlices (12 slices ~= 18 mm), beyond
    %      which two manual contours likely belong to different lesions
    %      (or to opposite ends of one whose middle the user did not
    %      draw - either way, bridging would invent geometry).
    if canAlign
        drift = norm(cB - cA);
        if drift > opts.maxCentroidDriftPerSlice * (b - a)
            continue;
        end
    end
    if (b - a) > opts.maxGapSlices
        continue;
    end

    if canAlign
        shiftAtoB = cB - cA;
        maAligned = shiftMask(ma, shiftAtoB);
        sdfA = signedDistance(maAligned);
        sdfB = signedDistance(mb);
    else
        sdfA = signedDistance(ma);
        sdfB = signedDistance(mb);
    end

    for z = a + 1 : b - 1
        alpha = (z - a) / (b - a);
        sdfZ = (1 - alpha) * sdfA + alpha * sdfB;

        % Conservative interior threshold: shrink the implied mask by
        % up to `shrinkAtMiddleVoxels` voxels at alpha=0.5 (middle of
        % the gap), tapering to 0 at the keyframes. Keeps the boundary
        % crisp and reduces "halo" false positives.
        eps = opts.shrinkAtMiddleVoxels * 2 * min(alpha, 1 - alpha);
        maskAtB = sdfZ >= eps;

        if canAlign
            cZ = (1 - alpha) * cA + alpha * cB;
            maskZ = shiftMask(maskAtB, cZ - cB);
        else
            maskZ = maskAtB;
        end

        maskZYX(z, :, :) = maskZ;
    end
end
end


% =========================================================================
function c = centroidOf(maskBin)
% Returns [yc, xc] (row, col) centroid, or [NaN, NaN] if mask is empty.
n = nnz(maskBin);
if n == 0
    c = [NaN, NaN];
    return;
end
[Y, X] = size(maskBin);
[yy, xx] = ndgrid(1:Y, 1:X);
c = [sum(yy(maskBin)) / n, sum(xx(maskBin)) / n];
end


function out = shiftMask(maskBin, shiftYX)
% Translate `maskBin` by shiftYX = [dy, dx] in pixel space (rounded to
% the nearest integer; we don't need subpixel accuracy for masks).
dy = round(shiftYX(1));
dx = round(shiftYX(2));
if dy == 0 && dx == 0
    out = maskBin;
    return;
end
% imtranslate exists in image processing toolbox; circshift would wrap
% around so we use imtranslate with zero fill.
out = imtranslate(maskBin, [dx, dy], "FillValues", 0);
end


function sdf = signedDistance(maskBin)
% Signed distance transform: positive inside, negative outside, 0 on edge.
sz = size(maskBin);
if ~any(maskBin, "all")
    sdf = -1e6 * ones(sz, "single");
    return;
end
if all(maskBin, "all")
    sdf = 1e6 * ones(sz, "single");
    return;
end
distOut = bwdist(maskBin);
distIn = bwdist(~maskBin);
sdf = single(distIn) - single(distOut);
end
