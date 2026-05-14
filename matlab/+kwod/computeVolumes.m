function metrics = computeVolumes(maskLiver, maskLesion, spacingXYZmm)
% computeVolumes Compute liver/lesion volume metrics.
%
% Inputs:
%   maskLiver     - logical [Z,Y,X] or []
%   maskLesion    - logical [Z,Y,X] or []
%   spacingXYZmm  - [dx,dy,dz]

arguments
    maskLiver
    maskLesion
    spacingXYZmm (1, 3) double
end

voxelVolCm3 = prod(spacingXYZmm) / 1000.0;

metrics = struct();
metrics.voxelVolumeCm3 = voxelVolCm3;

if ~isempty(maskLiver)
    liverVox = nnz(maskLiver);
    metrics.liverVoxels = liverVox;
    metrics.liverVolumeCm3 = liverVox * voxelVolCm3;
end

if ~isempty(maskLesion)
    lesionVox = nnz(maskLesion);
    metrics.lesionVoxels = lesionVox;
    metrics.lesionVolumeCm3 = lesionVox * voxelVolCm3;
end

if ~isempty(maskLiver) && ~isempty(maskLesion)
    denom = max(1, nnz(maskLiver));
    metrics.lesionPercentOfLiver = (nnz(maskLesion) / denom) * 100.0;
end

end

