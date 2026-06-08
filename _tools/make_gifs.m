function make_gifs()
% Build animated GIFs from the screen recordings + copy curated stills,
% into raport/media/ for the lab report.

proj = 'c:\New project\CAD watroba';
dl = fullfile(getenv('USERPROFILE'), 'Downloads');
outDir = fullfile(proj, 'raport', 'media');
if ~exist(outDir, 'dir'); mkdir(outDir); end

jobs = { ...
    'demo_watroba_guzy.gif',   'Запись экрана 2026-06-07 в 15.00.52.mp4', 0.5, 560; ...
    'demo_pomiar_roi.gif',     'Запись экрана 2026-06-07 в 14.19.04.mp4', 0.5, 560; ...
    'artefakt_plywajaca.gif',  'Запись экрана 2026-06-07 в 19.30.30.mp4', 0.5, 560};

for j = 1:size(jobs, 1)
    outName = jobs{j, 1};
    p = fullfile(dl, jobs{j, 2});
    step = jobs{j, 3};
    width = jobs{j, 4};
    outPath = fullfile(outDir, outName);
    fprintf('GIF %s\n', outName);
    if ~isfile(p); fprintf('  MISSING %s\n', p); continue; end
    v = VideoReader(p);
    ts = 0.3 : step : max(v.Duration - 0.3, 0.3);
    first = true;
    for i = 1:numel(ts)
        v.CurrentTime = ts(i);
        if ~hasFrame(v); break; end
        img = readFrame(v);
        sc = width / size(img, 2);
        if sc < 1; img = imresize(img, sc); end
        [A, map] = rgb2ind(img, 64);
        if first
            imwrite(A, map, outPath, 'gif', 'LoopCount', Inf, 'DelayTime', 0.18);
            first = false;
        else
            imwrite(A, map, outPath, 'gif', 'WriteMode', 'append', 'DelayTime', 0.18);
        end
    end
    d = dir(outPath);
    if ~isempty(d)
        fprintf('  wrote %s (%.1f KB, %d frames)\n', outName, d.bytes/1024, numel(ts));
    end
end

% Curated stills -> raport/media (renamed, descriptive)
stills = { ...
    '14.19.04', '14.19.04_05_t015.5.png', 'still_watroba_guz_segmentacja.png'; ...
    '14.19.04', '14.19.04_07_t023.0.png', 'still_pomiar_roi_kola.png'; ...
    '15.00.52', '15.00.52_06_t016.7.png', 'still_watroba_dwa_guzy.png'; ...
    '19.30.30', '19.30.30_06_t017.7.png', 'still_watroba_pelna.png'; ...
    '19.30.30', '19.30.30_08_t024.6.png', 'still_artefakt_plywajaca_maska.png'};
framesRoot = fullfile(proj, '_tools', 'frames');
for s = 1:size(stills, 1)
    src = fullfile(framesRoot, stills{s, 1}, stills{s, 2});
    dst = fullfile(outDir, stills{s, 3});
    if isfile(src)
        copyfile(src, dst);
        fprintf('  still %s\n', stills{s, 3});
    else
        fprintf('  MISSING still %s\n', src);
    end
end
fprintf('DONE\n');
end
