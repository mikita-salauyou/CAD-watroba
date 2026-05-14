function [removeMask, keepMask, planeMeta] = applyResectionPlane( ...
    liverMaskZYX, plane, spacingXYZmm)
% applyResectionPlane Split a liver mask by a vertical plane defined in axial view.
%
% The plane is specified by 2 endpoints `[y1, x1; y2, x2]` of a line drawn
% on the axial view (any single slice). It is extruded along Z, i.e. the
% same line cuts every slice. The half-space identified by `plane.side`
% (a +1/-1 sign) is the "remove" side; the rest is "keep".
%
% This is the prototype Couinaud-style resection: a vertical (Z-aligned)
% planar cut, like surgeons sketch on a single CT slice. A future
% extension can lift this to a fully oblique 3D plane (3 click points
% across slices), but vertical cuts already cover most "left vs right
% lobe" / "anterior vs posterior" educational use cases.
%
% Inputs:
%   liverMaskZYX : logical [Z, Y, X], the liver mask to split.
%   plane.points : 2x2 [y1, x1; y2, x2] line endpoints on axial view (px).
%   plane.side   : +1 or -1, which side of the line is "remove".
%   spacingXYZmm : 1x3 voxel spacing in mm [X, Y, Z].
%
% Outputs:
%   removeMask : logical [Z, Y, X], voxels of liverMask on the "remove" side.
%   keepMask   : logical [Z, Y, X], voxels of liverMask on the "keep" side.
%   planeMeta  : struct with fields:
%       .removeVolumeCm3, .keepVolumeCm3,
%       .removeVoxels, .keepVoxels,
%       .signedDistanceXY (Y x X single, distance from line for plotting).

arguments
    liverMaskZYX (:, :, :) logical
    plane (1, 1) struct
    spacingXYZmm (1, 3) double
end

if ~any(liverMaskZYX, "all")
    sz = size(liverMaskZYX);
    removeMask = false(sz);
    keepMask = false(sz);
    planeMeta = makeMeta(0, 0, 0, 0, zeros(sz(2), sz(3), "single"));
    return;
end

if ~isfield(plane, "points") || ~isequal(size(plane.points), [2, 2])
    error("kwod:applyResectionPlane:BadPlane", ...
        "plane.points must be 2x2 [y1, x1; y2, x2].");
end
if ~isfield(plane, "side")
    plane.side = 1;
end

sz = size(liverMaskZYX);
Y = sz(2);
X = sz(3);

% Line through (y1, x1) and (y2, x2). Signed distance for any point (y, x):
%     d = ((y2 - y1) * (x - x1) - (x2 - x1) * (y - y1)) / |dir|
% Sign tells us which side of the line we are on.
y1 = plane.points(1, 1);
x1 = plane.points(1, 2);
y2 = plane.points(2, 1);
x2 = plane.points(2, 2);

dy = y2 - y1;
dx = x2 - x1;
denom = max(hypot(dy, dx), eps);

[xx, yy] = meshgrid(1:X, 1:Y);
signedDistXY = single((dy .* (xx - x1) - dx .* (yy - y1)) ./ denom);

% "Remove" voxels are on the side selected by plane.side.
sideSelector = plane.side;
if sideSelector >= 0
    removeSliceMask = signedDistXY >= 0;
else
    removeSliceMask = signedDistXY < 0;
end

% Extrude through Z (same cut on every slice).
removeMask = false(sz);
keepMask = false(sz);
for z = 1:sz(1)
    sl = squeeze(liverMaskZYX(z, :, :));
    if ~any(sl, "all")
        continue;
    end
    removeMask(z, :, :) = sl & removeSliceMask;
    keepMask(z, :, :) = sl & ~removeSliceMask;
end

voxVolMm3 = prod(spacingXYZmm);
removeVox = nnz(removeMask);
keepVox = nnz(keepMask);

planeMeta = makeMeta( ...
    removeVox, keepVox, ...
    removeVox * voxVolMm3 / 1000, ...
    keepVox * voxVolMm3 / 1000, ...
    signedDistXY);
end


function meta = makeMeta(removeVox, keepVox, removeCm3, keepCm3, sdfXY)
meta = struct();
meta.removeVoxels = removeVox;
meta.keepVoxels = keepVox;
meta.removeVolumeCm3 = removeCm3;
meta.keepVolumeCm3 = keepCm3;
meta.signedDistanceXY = sdfXY;
end
