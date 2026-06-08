function extract_frames()
% Extract evenly spaced frames from the screen-recording videos into
% _tools/frames/<tag>/ as PNGs, for report analysis.

dl = getenv('USERPROFILE');
dl = fullfile(dl, 'Downloads');
vids = { ...
    '14.19.04', 'Запись экрана 2026-06-07 в 14.19.04.mp4'; ...
    '15.00.52', 'Запись экрана 2026-06-07 в 15.00.52.mp4'; ...
    '19.30.30', 'Запись экрана 2026-06-07 в 19.30.30.mp4'};

outRoot = fullfile('c:\New project\CAD watroba', '_tools', 'frames');
if ~exist(outRoot, 'dir'); mkdir(outRoot); end

nFrames = 9;  % evenly spaced samples per video

for k = 1:size(vids, 1)
    tag = vids{k, 1};
    p = fullfile(dl, vids{k, 2});
    fprintf('VIDEO %s -> %s\n', tag, p);
    if ~isfile(p)
        fprintf('  MISSING\n');
        continue;
    end
    outDir = fullfile(outRoot, tag);
    if ~exist(outDir, 'dir'); mkdir(outDir); end
    try
        v = VideoReader(p);
        dur = v.Duration;
        fprintf('  dur=%.1fs  %dx%d  %.2ffps\n', dur, v.Width, v.Height, v.FrameRate);
        ts = linspace(0.5, max(dur - 0.5, 0.5), nFrames);
        for i = 1:numel(ts)
            v.CurrentTime = ts(i);
            if ~hasFrame(v); break; end
            img = readFrame(v);
            % downscale to keep files small
            scale = 900 / size(img, 2);
            if scale < 1
                img = imresize(img, scale);
            end
            fn = fullfile(outDir, sprintf('%s_%02d_t%05.1f.png', tag, i, ts(i)));
            imwrite(img, fn);
            fprintf('  wrote %s\n', fn);
        end
    catch ex
        fprintf('  ERROR: %s\n', ex.message);
    end
end
fprintf('DONE\n');
end
