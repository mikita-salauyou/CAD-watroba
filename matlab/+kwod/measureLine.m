function info = measureLine(points, spacingXYZmm)
% measureLine Compute physical length of a 2D line drawn on an axial slice.
%
%   points       : [x1 y1; x2 y2] in image data coordinates (col, row).
%   spacingXYZmm : [dx, dy, dz] in mm.
%
%   Returns struct with:
%       lengthMm   : physical length in mm
%       midpoint   : [x, y] midpoint in image coordinates (for label)

arguments
    points (2, 2) double
    spacingXYZmm (1, 3) double
end

dx = spacingXYZmm(1);
dy = spacingXYZmm(2);

dxPx = points(2, 1) - points(1, 1);
dyPx = points(2, 2) - points(1, 2);

info = struct();
info.lengthMm = sqrt((dxPx * dx) ^ 2 + (dyPx * dy) ^ 2);
info.midpoint = mean(points, 1);
end
