function ref = loadReferenceMasks(folderPath, expectedShapeZYX)
% loadReferenceMasks Load IRCAD-style ground-truth masks.
%
%   IRCAD layout per study:
%       <study>/MASKS_DICOM/liver/        <- DICOM stack of binary mask
%       <study>/MASKS_DICOM/livertumor01/
%       <study>/MASKS_DICOM/livertumor02/
%       ...                               (also bone/, kidney/, etc.)
%
%   Some IRCAD bundles wrap an extra "MASKS_DICOM" folder, so we
%   transparently drill into it.
%
%   Returns:
%       ref.liver       : logical [Z,Y,X], may be all-false if not present
%       ref.lesion      : logical [Z,Y,X], union of livertumor* / livercyst*
%       ref.liverFolder : char, source subfolder for liver
%       ref.lesionFolders : string array, subfolders merged into lesion mask
%       ref.skipped     : string array, subfolders that could not be read

arguments
    folderPath (1, :) char
    expectedShapeZYX (1, 3) double
end

actual = resolveMasksFolder(folderPath);

entries = dir(actual);
entries = entries([entries.isdir]);
names = string({entries.name});
names = names(~ismember(names, [".", ".."]));
names = names(~startsWith(names, "."));

ref = struct();
ref.liver = false(expectedShapeZYX);
ref.lesion = false(expectedShapeZYX);
ref.liverFolder = '';
ref.lesionFolders = strings(0, 1);
ref.skipped = strings(0, 1);

for i = 1:numel(names)
    n = names(i);
    nLower = lower(n);
    sub = fullfile(actual, char(n));

    isLiver = strcmp(nLower, "liver");
    isLesion = startsWith(nLower, "livertumor") || ...
               startsWith(nLower, "livercyst") || ...
               startsWith(nLower, "tumor") || ...
               startsWith(nLower, "metastasis");

    if ~isLiver && ~isLesion
        continue;
    end

    try
        [vol, ~] = dicomreadVolume(sub);
    catch
        ref.skipped(end + 1, 1) = n;
        continue;
    end

    vol = squeeze(vol);
    if ndims(vol) ~= 3
        ref.skipped(end + 1, 1) = n;
        continue;
    end

    m = permute(vol, [3, 1, 2]) > 0;
    if ~isequal(size(m), expectedShapeZYX)
        ref.skipped(end + 1, 1) = n + " (shape mismatch)";
        continue;
    end

    if isLiver
        ref.liver = m;
        ref.liverFolder = char(n);
    else
        ref.lesion = ref.lesion | m;
        ref.lesionFolders(end + 1, 1) = n;
    end
end

if ~any(ref.liver, "all") && isempty(ref.lesionFolders)
    error("No 'liver' or 'livertumor*' subfolders found in %s.", actual);
end

end


function out = resolveMasksFolder(p)
out = p;
e = dir(p);
e = e([e.isdir]);
names = string({e.name});

if any(strcmpi(names, "liver"))
    return;
end

masksHit = strcmpi(names, "MASKS_DICOM");
if any(masksHit)
    out = fullfile(p, char(names(find(masksHit, 1))));
    return;
end

visible = names(~startsWith(names, ".") & ~ismember(names, [".", ".."]));
if numel(visible) == 1
    out = fullfile(p, char(visible));
end
end
