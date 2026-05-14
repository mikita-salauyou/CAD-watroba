function info = measureCircle(slice2d, mask2d, center, radiusPx, spacingXYZmm)
% measureCircle Compute geometric and intensity statistics of a circular ROI.
%
%   slice2d     : single/double image slice (HU values).
%   mask2d      : logical 2D mask of the circle ROI (same size as slice).
%   center      : [x, y] in image data coordinates (col, row).
%   radiusPx    : circle radius in pixels (column units).
%   spacingXYZmm: [dx, dy, dz] in mm.
%
%   Returns struct with:
%       center        : [x, y]
%       radiusPx      : pixel radius (kept for rendering)
%       diameterMm    : 2 * radius in mm using mean of dx, dy
%       areaCm2       : actual mask area in cm^2 (uses dx * dy)
%       voxelsInRoi   : number of pixels inside the ROI
%       meanHU, stdHU, minHU, maxHU : intensity statistics inside the ROI

arguments
    slice2d {mustBeNumeric}
    mask2d  logical
    center  (1, 2) double
    radiusPx (1, 1) double
    spacingXYZmm (1, 3) double
end

if ~isequal(size(slice2d), size(mask2d))
    error("measureCircle: slice and mask must have the same size.");
end

dx = spacingXYZmm(1);
dy = spacingXYZmm(2);

info = struct();
info.center = center;
info.radiusPx = radiusPx;
info.diameterMm = 2 * radiusPx * mean([dx, dy]);

n = nnz(mask2d);
info.voxelsInRoi = n;
info.areaCm2 = n * dx * dy / 100;

if n == 0
    info.meanHU = NaN;
    info.stdHU = NaN;
    info.minHU = NaN;
    info.maxHU = NaN;
    return;
end

vals = double(slice2d(mask2d));
info.meanHU = mean(vals);
info.stdHU = std(vals);
info.minHU = min(vals);
info.maxHU = max(vals);
end
