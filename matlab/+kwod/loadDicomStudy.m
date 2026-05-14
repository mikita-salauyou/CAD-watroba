function study = loadDicomStudy(folderPath)
% loadDicomStudy Load a 3D CT series from a DICOM folder.
%
% Accepts a folder that either:
%   - directly contains DICOM slices, or
%   - contains a subfolder with DICOM slices (e.g. "PATIENT_DICOM", "DICOM",
%     "IMAGES") - typical for IRCAD-style datasets.
%
% Returns the same fields as the app expects:
%   volumeZYX      - single array [Z,Y,X]
%   shapeZYX       - [Z,Y,X]
%   spacingXYZmm   - [dx,dy,dz] in mm
%   filePath       - folder that was actually used

arguments
    folderPath (1, :) char
end

if ~isfolder(folderPath)
    error("Folder not found: %s", folderPath);
end

seriesFolder = resolveSeriesFolder(folderPath);

try
    [vol, spatial] = dicomreadVolume(seriesFolder);
catch ex
    error("DICOM read failed for folder:\n  %s\n\nDetails: %s\n\nHint: pick the folder that directly contains a single CT series (e.g. PATIENT_DICOM).", ...
        seriesFolder, ex.message);
end

% dicomreadVolume returns [rows, cols, samplesPerPixel, slices] (4D).
% For CT (grayscale) samplesPerPixel == 1, so squeeze to 3D.
vol = squeeze(vol);
vol = single(vol);

if ndims(vol) ~= 3
    error("DICOM volume is not 3D after squeeze (got %dD). Pick a folder with a single grayscale CT series.", ndims(vol));
end

% Layout from dicomreadVolume: [rows, cols, slices] == [Y, X, Z]
volumeZYX = permute(vol, [3, 1, 2]);
shapeZYX = size(volumeZYX);

spacingXYZmm = resolveSpacing(spatial, seriesFolder);

study = struct();
study.volumeZYX = volumeZYX;
study.shapeZYX = shapeZYX;
study.spacingXYZmm = spacingXYZmm;
study.filePath = seriesFolder;

end

function out = resolveSeriesFolder(folderPath)
% Try the folder directly first. If it seems to contain only subfolders, drill into
% a conventional DICOM subfolder if one exists.

out = folderPath;

if hasDicomLikeFiles(folderPath)
    return;
end

candidates = { ...
    'PATIENT_DICOM', ...
    'DICOM', ...
    'IMAGES', ...
    'ST_000000', ...
    'ST000000'};

entries = dir(folderPath);
entries = entries([entries.isdir]);
names = {entries.name};

% exact match first
for i = 1:numel(candidates)
    hit = strcmpi(names, candidates{i});
    if any(hit)
        sub = fullfile(folderPath, names{find(hit, 1)});
        if hasDicomLikeFiles(sub)
            out = sub;
            return;
        end
    end
end

% If there is exactly one non-hidden subfolder and current folder has no DICOM, drill in.
visible = entries(~startsWith(string(names), "."));
if numel(visible) == 1
    sub = fullfile(folderPath, visible(1).name);
    if hasDicomLikeFiles(sub)
        out = sub;
        return;
    end
end

% Otherwise fall back to original folder; let dicomreadVolume try.
end

function tf = hasDicomLikeFiles(folderPath)
tf = false;
files = dir(folderPath);
files = files(~[files.isdir]);
if isempty(files)
    return;
end

for i = 1:min(numel(files), 50)
    name = files(i).name;
    [~, ~, ext] = fileparts(name);
    extLower = lower(ext);
    if ~isempty(extLower) && ~any(strcmp(extLower, {'.dcm', '.dicom', '.ima'}))
        continue;
    end
    try
        if isdicom(fullfile(folderPath, name))
            tf = true;
            return;
        end
    catch
    end
end
end

function spacing = resolveSpacing(spatial, seriesFolder)
dx = 1.0;
dy = 1.0;
dz = 1.0;

% Case 1: struct (R2018b+ typical)
%   spatial.PixelSpacings       [N x 2] -> [row=dy, col=dx]
%   spatial.PatientPositions    [N x 3] -> z spacing from Z diffs
if isstruct(spatial)
    if isfield(spatial, 'PixelSpacings') && ~isempty(spatial.PixelSpacings)
        ps = double(spatial.PixelSpacings(1, :));
        if numel(ps) >= 2
            dy = ps(1);
            dx = ps(2);
        end
    end
    if isfield(spatial, 'PatientPositions') && size(spatial.PatientPositions, 1) >= 2
        zpos = double(spatial.PatientPositions(:, 3));
        diffs = abs(diff(zpos));
        diffs = diffs(diffs > 0);
        if ~isempty(diffs)
            dz = median(diffs);
        end
    end
end

% Case 2: imref3d object
if isobject(spatial)
    try
        if isprop(spatial, 'PixelExtentInWorldX')
            dx = double(spatial.PixelExtentInWorldX);
        end
        if isprop(spatial, 'PixelExtentInWorldY')
            dy = double(spatial.PixelExtentInWorldY);
        end
        if isprop(spatial, 'PixelExtentInWorldZ')
            dz = double(spatial.PixelExtentInWorldZ);
        end
    catch
    end
end

% Last-resort fallback: read a single DICOM header to get PixelSpacing / SliceThickness.
if dx == 1.0 && dy == 1.0
    try
        files = dir(seriesFolder);
        files = files(~[files.isdir]);
        for i = 1:min(numel(files), 20)
            f = fullfile(seriesFolder, files(i).name);
            try
                info = dicominfo(f);
                if isfield(info, 'PixelSpacing') && numel(info.PixelSpacing) >= 2
                    dy = double(info.PixelSpacing(1));
                    dx = double(info.PixelSpacing(2));
                end
                if isfield(info, 'SliceThickness')
                    dz = double(info.SliceThickness);
                end
                break;
            catch
            end
        end
    catch
    end
end

spacing = [dx, dy, dz];
end
