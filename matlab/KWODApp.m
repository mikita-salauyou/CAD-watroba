classdef KWODApp < handle
    % KWODApp MATLAB desktop prototype for CT liver CAD
    % (semi-automatic workflow per project concept).
    %
    % Workflow:
    %   1. Open DICOM folder.
    %   2. Scroll to a slice where the liver is clearly visible.
    %   3. Press "Seed liver" and click inside the liver on the image.
    %   4. Press "Seed lesion" and click inside a focal lesion.
    %      (Click must be inside the already-grown liver mask.)
    %   5. Optional: place rulers / circular ROIs for measurements.
    %   6. Optional: load IRCAD reference masks to compute Dice.
    %
    % Notes:
    %   - Window/Level is fixed to a liver preset (WL 60 / WW 180).
    %   - Mask overlays can be toggled independently.
    %   - Measurements are tied to the slice they were drawn on and
    %     re-appear when you scroll back.

    properties (Constant, Access = private)
        WindowLevel = 60
        WindowWidth = 180
        LiverColor = [0.15, 0.85, 0.35]
        LesionColor = [1.00, 0.25, 0.20]
        LiverAlpha = 0.22
        LesionAlpha = 0.55
        LiverToleranceDefault = 40
        LesionToleranceDefault = 25

        % Measurement / reference colors: saturated + dark for readability
        % on top of grayscale CT.
        RulerColor = [0.95, 0.40, 0.00]      % deep saturated orange
        RoiColor = [0.00, 0.55, 0.85]        % deep saturated cyan
        RefLiverColor = [0.10, 0.30, 0.90]   % deep saturated blue
        RefLesionColor = [0.85, 0.05, 0.55]  % deep saturated magenta

        LabelFontSize = 13
        RulerLineWidth = 2.5
        RoiLineWidth = 2.5
    end

    properties (Access = private)
        Fig
        Ax
        ImgHandle
        OpenDicomBtn
        ManualLiverBtn
        ManualLesionBtn
        EraserBtn
        InterpolateBtn
        ClearMasksBtn
        ClearSliceBtn
        RulerBtn
        CircleBtn
        ClearMeasureBtn
        LoadRefBtn
        ShowLiverCb
        ShowLesionCb
        ShowRefCb
        SliceSlider
        SliceLabel
        PrevBigBtn
        PrevBtn
        NextBtn
        NextBigBtn
        MetricsArea
        StatusLabel
    end

    properties (Access = private)
        Study struct = struct()
        MaskLiver logical = logical.empty
        MaskLesion logical = logical.empty
        LiverKeyframes double = []     % Z indices of manually drawn liver slices
        LesionKeyframes double = []    % Z indices of manually drawn lesion slices
        RefLiver logical = logical.empty
        RefLesion logical = logical.empty
        RefInfo struct = struct()
        Measurements cell = {}
        CurrentZ double = 1
        % Seed mode removed (manual-only workflow)
    end

    methods
        function show(app)
            app.buildUI();
            app.setStatus("Ready. Open a DICOM study.");
        end
    end

    methods (Access = private)
        function buildUI(app)
            app.Fig = uifigure( ...
                "Name", "KWOD CAD Liver Prototype (MATLAB)", ...
                "Position", [60, 60, 1380, 860], ...
                "Color", [0.08, 0.09, 0.13], ...
                "KeyPressFcn", @(~, evt) app.onKeyPress(evt));

            gl = uigridlayout(app.Fig, [4, 2]);
            gl.RowHeight = {44, 40, "1x", 200};
            gl.ColumnWidth = {"1x", 360};
            gl.Padding = [10, 10, 10, 10];
            gl.RowSpacing = 6;
            gl.ColumnSpacing = 8;
            gl.BackgroundColor = [0.08, 0.09, 0.13];

            % --- Top toolbar: DICOM + manual segmentation only --------
            topBar = uigridlayout(gl, [1, 9]);
            topBar.Layout.Row = 1;
            topBar.Layout.Column = [1, 2];
            topBar.ColumnWidth = {160, 110, 110, 80, 100, 90, 90, "1x", 160};
            topBar.RowHeight = {"1x"};
            topBar.Padding = [0, 0, 0, 0];
            topBar.BackgroundColor = [0.08, 0.09, 0.13];

            app.OpenDicomBtn = uibutton(topBar, ...
                "Text", "Open DICOM Folder...", ...
                "ButtonPushedFcn", @(~, ~) app.onOpenDicom());
            app.OpenDicomBtn.Layout.Column = 1;

            app.ManualLiverBtn = uibutton(topBar, ...
                "Text", "Manual liver", ...
                "BackgroundColor", [0.20, 0.45, 0.30], ...
                "FontColor", [0.95, 1.0, 0.95], ...
                "ButtonPushedFcn", @(~, ~) app.onManualDraw("liver"));
            app.ManualLiverBtn.Layout.Column = 2;

            app.ManualLesionBtn = uibutton(topBar, ...
                "Text", "Manual lesion", ...
                "BackgroundColor", [0.55, 0.22, 0.22], ...
                "FontColor", [1.0, 0.95, 0.95], ...
                "ButtonPushedFcn", @(~, ~) app.onManualDraw("lesion"));
            app.ManualLesionBtn.Layout.Column = 3;

            app.EraserBtn = uibutton(topBar, ...
                "Text", "Eraser", ...
                "BackgroundColor", [0.8, 0.6, 0.1], ... 
                "FontColor", [1.0, 1.0, 1.0], ...
                "ButtonPushedFcn", @(~, ~) app.onEraserDraw());
            app.EraserBtn.Layout.Column = 4;

            app.InterpolateBtn = uibutton(topBar, ...
                "Text", "Interpolate", ...
                "BackgroundColor", [0.25, 0.30, 0.55], ...
                "FontColor", [0.95, 0.97, 1.0], ...
                "ButtonPushedFcn", @(~, ~) app.onInterpolateMasks());
            app.InterpolateBtn.Layout.Column = 5;

            app.ClearMasksBtn = uibutton(topBar, ...
                "Text", "Clear all", ...
                "ButtonPushedFcn", @(~, ~) app.onClearMasks());
            app.ClearMasksBtn.Layout.Column = 6;

            app.ClearSliceBtn = uibutton(topBar, ...
                "Text", "Clear slice", ...
                "ButtonPushedFcn", @(~, ~) app.onClearCurrentSlice());
            app.ClearSliceBtn.Layout.Column = 7;

            app.StatusLabel = uilabel(topBar, ...
                "Text", "No study loaded", ...
                "FontColor", [0.65, 0.72, 0.9], ...
                "HorizontalAlignment", "left");
            app.StatusLabel.Layout.Column = 8;

            wwLabel = uilabel(topBar, ...
                "Text", sprintf("WL %d / WW %d", app.WindowLevel, app.WindowWidth), ...
                "FontColor", [0.78, 0.85, 1.0], ...
                "HorizontalAlignment", "right");
            wwLabel.Layout.Column = 9;

            % --- Second toolbar: review tools ------------------------
            toolBar = uigridlayout(gl, [1, 8]);
            toolBar.Layout.Row = 2;
            toolBar.Layout.Column = [1, 2];
            toolBar.ColumnWidth = {90, 100, 80, 70, 90, 110, 165, "1x"};
            toolBar.RowHeight = {"1x"};
            toolBar.Padding = [0, 0, 0, 0];
            toolBar.BackgroundColor = [0.08, 0.09, 0.13];

            app.ShowLiverCb = uicheckbox(toolBar, ...
                "Text", "Show liver", ...
                "Value", true, ...
                "FontColor", [0.85, 0.95, 0.88], ...
                "ValueChangedFcn", @(~, ~) app.renderSlice());
            app.ShowLiverCb.Layout.Column = 1;

            app.ShowLesionCb = uicheckbox(toolBar, ...
                "Text", "Show lesions", ...
                "Value", true, ...
                "FontColor", [1.00, 0.80, 0.75], ...
                "ValueChangedFcn", @(~, ~) app.renderSlice());
            app.ShowLesionCb.Layout.Column = 2;

            app.ShowRefCb = uicheckbox(toolBar, ...
                "Text", "Show ref", ...
                "Value", true, ...
                "FontColor", [0.75, 0.85, 1.00], ...
                "ValueChangedFcn", @(~, ~) app.renderSlice());
            app.ShowRefCb.Layout.Column = 3;

            app.RulerBtn = uibutton(toolBar, ...
                "Text", "Ruler", ...
                "ButtonPushedFcn", @(~, ~) app.onAddRuler());
            app.RulerBtn.Layout.Column = 4;

            app.CircleBtn = uibutton(toolBar, ...
                "Text", "Circle ROI", ...
                "ButtonPushedFcn", @(~, ~) app.onAddCircle());
            app.CircleBtn.Layout.Column = 5;

            app.ClearMeasureBtn = uibutton(toolBar, ...
                "Text", "Clear measures", ...
                "ButtonPushedFcn", @(~, ~) app.onClearMeasurements());
            app.ClearMeasureBtn.Layout.Column = 6;

            app.LoadRefBtn = uibutton(toolBar, ...
                "Text", "Load reference (IRCAD)", ...
                "ButtonPushedFcn", @(~, ~) app.onLoadReference());
            app.LoadRefBtn.Layout.Column = 7;

            % --- Axes ------------------------------------------------
            app.Ax = uiaxes(gl);
            app.Ax.Layout.Row = 3;
            app.Ax.Layout.Column = 1;
            app.Ax.BackgroundColor = [0, 0, 0];
            axis(app.Ax, "image");
            app.Ax.XTick = [];
            app.Ax.YTick = [];
            app.Ax.Toolbar.Visible = "off";
            disableDefaultInteractivity(app.Ax);

            % --- Side panel ------------------------------------------
            sidePanel = uigridlayout(gl, [5, 2]);
            sidePanel.Layout.Row = 3;
            sidePanel.Layout.Column = 2;
            sidePanel.RowHeight = {22, 40, 32, 22, "1x"};
            sidePanel.ColumnWidth = {130, "1x"};
            sidePanel.Padding = [10, 10, 10, 10];
            sidePanel.BackgroundColor = [0.11, 0.13, 0.22];

            sliceTitle = uilabel(sidePanel, "Text", "Slice Z", ...
                "FontColor", [0.85, 0.9, 1.0]);
            sliceTitle.Layout.Row = 1;
            sliceTitle.Layout.Column = 1;

            app.SliceLabel = uilabel(sidePanel, "Text", "-", ...
                "FontColor", [0.85, 0.9, 1.0]);
            app.SliceLabel.Layout.Row = 1;
            app.SliceLabel.Layout.Column = 2;

            app.SliceSlider = uislider(sidePanel, ...
                "Limits", [1, 2], ...
                "Value", 1, ...
                "MajorTicks", [], ...
                "MinorTicks", [], ...
                "ValueChangingFcn", @(~, evt) app.onSliceChange(evt.Value), ...
                "ValueChangedFcn", @(~, evt) app.onSliceChange(evt.Value));
            app.SliceSlider.Layout.Row = 2;
            app.SliceSlider.Layout.Column = [1, 2];

            % --- Slice navigation buttons --------------------------------
            navGrid = uigridlayout(sidePanel, [1, 4]);
            navGrid.Layout.Row = 3;
            navGrid.Layout.Column = [1, 2];
            navGrid.ColumnWidth = {"1x", "1x", "1x", "1x"};
            navGrid.RowHeight = {"1x"};
            navGrid.Padding = [0, 0, 0, 0];
            navGrid.ColumnSpacing = 4;
            navGrid.BackgroundColor = [0.11, 0.13, 0.22];

            app.PrevBigBtn = uibutton(navGrid, ...
                "Text", "<< -10", ...
                "BackgroundColor", [0.18, 0.22, 0.35], ...
                "FontColor", [0.92, 0.95, 1.0], ...
                "Tooltip", "Jump back 10 slices  (PageDown)", ...
                "ButtonPushedFcn", @(~, ~) app.onSliceStep(-10));
            app.PrevBigBtn.Layout.Column = 1;

            app.PrevBtn = uibutton(navGrid, ...
                "Text", "< -1", ...
                "BackgroundColor", [0.20, 0.28, 0.45], ...
                "FontColor", [0.95, 0.98, 1.0], ...
                "Tooltip", "Previous slice  (Left arrow)", ...
                "ButtonPushedFcn", @(~, ~) app.onSliceStep(-1));
            app.PrevBtn.Layout.Column = 2;

            app.NextBtn = uibutton(navGrid, ...
                "Text", "+1 >", ...
                "BackgroundColor", [0.20, 0.28, 0.45], ...
                "FontColor", [0.95, 0.98, 1.0], ...
                "Tooltip", "Next slice  (Right arrow)", ...
                "ButtonPushedFcn", @(~, ~) app.onSliceStep(1));
            app.NextBtn.Layout.Column = 3;

            app.NextBigBtn = uibutton(navGrid, ...
                "Text", "+10 >>", ...
                "BackgroundColor", [0.18, 0.22, 0.35], ...
                "FontColor", [0.92, 0.95, 1.0], ...
                "Tooltip", "Jump forward 10 slices  (PageUp)", ...
                "ButtonPushedFcn", @(~, ~) app.onSliceStep(10));
            app.NextBigBtn.Layout.Column = 4;

            legendLiver = uilabel(sidePanel, ...
                "Text", "Liver  -  green   |   Lesion  -  red", ...
                "FontColor", [0.85, 0.92, 0.95]);
            legendLiver.Layout.Row = 4;
            legendLiver.Layout.Column = [1, 2];

            legendRef = uilabel(sidePanel, ...
                "Text", "Reference  -  blue contour (liver) / pink (lesion)", ...
                "FontColor", [0.7, 0.85, 1.0]);
            legendRef.Layout.Row = 5;
            legendRef.Layout.Column = [1, 2];

            % (Manual-only UI) Removed tolerance fields, NIfTI mask load,
            % and the right-side long description text per request.

            % --- Metrics panel ---------------------------------------
            metricsPanel = uipanel(gl, ...
                "Title", "Metrics", ...
                "TitlePosition", "lefttop", ...
                "BackgroundColor", [0.11, 0.13, 0.22], ...
                "ForegroundColor", [0.9, 0.94, 1.0]);
            metricsPanel.Layout.Row = 4;
            metricsPanel.Layout.Column = [1, 2];

            metricsGrid = uigridlayout(metricsPanel, [1, 1]);
            metricsGrid.Padding = [8, 8, 8, 8];
            metricsGrid.BackgroundColor = [0.11, 0.13, 0.22];

            app.MetricsArea = uitextarea(metricsGrid, ...
                "Editable", "off", ...
                "Value", {'No metrics yet. Load a study and place seeds.'});
            app.MetricsArea.Layout.Row = 1;
            app.MetricsArea.Layout.Column = 1;
        end

        % ================ Loading ======================================

        function tf = confirmDiscardWork(app)
            % Ask before throwing away masks / measurements.
            % Returns true if user wants to continue.
            hasWork = (~isempty(app.MaskLiver) && any(app.MaskLiver, "all")) || ...
                      (~isempty(app.MaskLesion) && any(app.MaskLesion, "all")) || ...
                      ~isempty(app.Measurements);
            if ~hasWork
                tf = true;
                return;
            end
            res = uiconfirm(app.Fig, ...
                "Loading a NEW study will discard the current masks and " + ...
                "measurements. Continue?", ...
                "Discard current work?", ...
                "Options", ["Discard and load", "Cancel"], ...
                "DefaultOption", "Cancel", ...
                "CancelOption", "Cancel");
            tf = (res == "Discard and load");
        end

        function onOpenDicom(app)
            if ~app.confirmDiscardWork()
                app.setStatus("Open DICOM cancelled.");
                return;
            end

            folder = uigetdir("", "Select folder containing a DICOM CT series");
            if isequal(folder, 0)
                return;
            end

            app.setStatus("Loading DICOM...");
            drawnow;

            try
                study = kwod.loadDicomStudy(folder);
            catch ex
                uialert(app.Fig, ex.message, "Load error");
                app.setStatus("Load failed.");
                return;
            end

            app.applyStudy(study);
            app.setStatus(sprintf("Loaded DICOM: %s  [Z,Y,X]=[%d,%d,%d]", ...
                app.Study.filePath, app.Study.shapeZYX(1), app.Study.shapeZYX(2), app.Study.shapeZYX(3)));
        end

        function applyStudy(app, study)
            app.Study = study;
            app.MaskLiver = false(app.Study.shapeZYX);
            app.MaskLesion = false(app.Study.shapeZYX);
            app.LiverKeyframes = [];
            app.LesionKeyframes = [];
            app.RefLiver = logical.empty;
            app.RefLesion = logical.empty;
            app.RefInfo = struct();
            app.Measurements = {};
            % manual-only

            app.CurrentZ = max(1, round(app.Study.shapeZYX(1) / 2));
            app.SliceSlider.Limits = [1, max(2, app.Study.shapeZYX(1))];
            app.SliceSlider.Value = app.CurrentZ;

            app.updateSliceLabel();
            app.renderSlice();
            app.updateMetrics();
        end

        function onClearMasks(app)
            if isempty(fieldnames(app.Study))
                return;
            end
            app.MaskLiver = false(app.Study.shapeZYX);
            app.MaskLesion = false(app.Study.shapeZYX);
            app.LiverKeyframes = [];
            app.LesionKeyframes = [];
            % manual-only
            app.renderSlice();
            app.updateMetrics();
            app.setStatus("Masks and keyframes cleared.");
        end

        function onClearCurrentSlice(app)
            if isempty(fieldnames(app.Study))
                return;
            end
            z = app.CurrentZ;
            didClear = false;
            if ~isempty(app.MaskLiver) && any(app.MaskLiver(z, :, :), "all")
                app.MaskLiver(z, :, :) = false;
                app.LiverKeyframes(app.LiverKeyframes == z) = [];
                didClear = true;
            end
            if ~isempty(app.MaskLesion) && any(app.MaskLesion(z, :, :), "all")
                app.MaskLesion(z, :, :) = false;
                app.LesionKeyframes(app.LesionKeyframes == z) = [];
                didClear = true;
            end
            if didClear
                app.renderSlice();        
                app.updateMetrics();      
                app.updateSliceLabel();   
                app.setStatus(sprintf("Cleared all masks on slice %d.", z));
            else
                app.setStatus(sprintf("No masks to clear on slice %d.", z));
            end
        end

        function onEraserDraw(app)
            if isempty(fieldnames(app.Study))
                return;
            end

            z = app.CurrentZ;
            app.setStatus(sprintf( ...
                "Eraser on slice %d: PRESS LMB and DRAG around the area to remove, RELEASE to finish.", z));
            drawnow;

            roi = [];
            try
                roi = drawfreehand(app.Ax, ...
                    "Color", [0.9, 0.8, 0.2], ... 
                    "LineWidth", 2.5, ...
                    "Smoothing", 2, ...
                    "Closed", true, ...
                    "FaceAlpha", 0.0, ...
                    "InteractionsAllowed", "none");
            catch ex
                app.setStatus(sprintf("Eraser failed: %s", ex.message));
                return;
            end

            if isempty(roi) || ~isvalid(roi) || ...
                    isempty(roi.Position) || size(roi.Position, 1) < 3
                if ~isempty(roi) && isvalid(roi)
                    delete(roi);
                end
                app.setStatus("Eraser cancelled.");
                return;
            end

            try
                mask2d = createMask(roi, app.ImgHandle);
            catch
                mask2d = createMask(roi);
            end
            delete(roi);

            if isempty(mask2d) || ~any(mask2d, "all")
                app.setStatus("Eraser produced an empty area.");
                return;
            end

            sz = app.Study.shapeZYX;
            if ~isequal(size(mask2d), [sz(2), sz(3)])
                return;
            end

            didErase = false;

            if ~isempty(app.MaskLiver) && any(app.MaskLiver(z, :, :), "all")
                sliceLiver = squeeze(app.MaskLiver(z, :, :));
                app.MaskLiver(z, :, :) = sliceLiver & ~mask2d;
                didErase = true;
            end

            if ~isempty(app.MaskLesion) && any(app.MaskLesion(z, :, :), "all")
                sliceLesion = squeeze(app.MaskLesion(z, :, :));
                app.MaskLesion(z, :, :) = sliceLesion & ~mask2d;
                didErase = true;
            end

            if didErase
                app.renderSlice();
                app.updateMetrics();
                app.setStatus(sprintf("Erased selected area on slice %d.", z));
            else
                app.setStatus("No masks to erase in the selected area.");
            end
        end

        % ================ Manual polygon segmentation ===================

        function onManualDraw(app, target)
            % Trace a contour on the current slice with the mouse (press
            % LMB, drag along the organ boundary, release). The traced
            % polygon is stored as a 2D mask on the current slice and
            % `z` is added as a keyframe for `target` ("liver" / "lesion").
            if isempty(fieldnames(app.Study))
                uialert(app.Fig, "Load a CT study first.", "No study");
                return;
            end
            target = string(target);
            % manual-only

            z = app.CurrentZ;

            app.setStatus(sprintf( ...
                "Manual %s on slice %d:  PRESS LMB and DRAG along the boundary, RELEASE to finish.", ...
                target, z));
            drawnow;

            color = app.LiverColor;
            if target == "lesion"
                color = app.LesionColor;
            end

            roi = [];
            try
                roi = drawfreehand(app.Ax, ...
                    "Color", color, ...
                    "LineWidth", 2.5, ...
                    "Smoothing", 2, ...
                    "Closed", true, ...
                    "FaceAlpha", 0.0, ...
                    "InteractionsAllowed", "none");
            catch ex
                app.setStatus(sprintf("Manual draw failed: %s", ex.message));
                return;
            end

            if isempty(roi) || ~isvalid(roi) || ...
                    isempty(roi.Position) || size(roi.Position, 1) < 3
                if ~isempty(roi) && isvalid(roi)
                    delete(roi);
                end
                app.setStatus("Manual draw cancelled - too few points (need to drag a contour).");
                return;
            end

            try
                mask2d = createMask(roi, app.ImgHandle);
            catch
                mask2d = createMask(roi);
            end
            delete(roi);
            if isempty(mask2d) || ~any(mask2d, "all")
                app.setStatus("Manual draw produced an empty mask - try again with a larger contour.");
                return;
            end
            % Sanity: align mask size with slice [Y, X]
            sz = app.Study.shapeZYX;
            if ~isequal(size(mask2d), [sz(2), sz(3)])
                app.setStatus(sprintf( ...
                    "Manual mask size mismatch [%d %d] vs slice [%d %d] - ignored.", ...
                    size(mask2d, 1), size(mask2d, 2), sz(2), sz(3)));
                return;
            end
            app.setStatus(sprintf("Refining %s contour (Active Contours)...", target));
            drawnow;

            sl = squeeze(app.Study.volumeZYX(z, :, :));
            wl = app.WindowLevel;
            ww = max(1.0, app.WindowWidth);
            lo = wl - ww / 2;
            hi = wl + ww / 2;
            imgDisp = (min(max(sl, lo), hi) - lo) ./ (hi - lo);

            if target == "liver"
                maxDilation = 12;
                allowedZone = imdilate(mask2d, strel('disk', maxDilation));
                imgDisp(~allowedZone) = 0; 
                
                numIterations = 50; 
                mask2d = activecontour(imgDisp, mask2d, numIterations, 'Chan-Vese', ...
                    'SmoothFactor', 1.5);
            else
                maxDilation = 8; 
                allowedZone = imdilate(mask2d, strel('disk', maxDilation));
                imgDisp(~allowedZone) = 0;
                
                numIterations = 35; 
                mask2d = activecontour(imgDisp, mask2d, numIterations, 'edge', ...
                    'SmoothFactor', 1.0, ...
                    'ContractionBias', 0.1);
            end
            
            if ~any(mask2d, "all")
                app.setStatus("Active contour collapsed to zero. Try drawing closer to the edge.");
                return;
            end
          

            if target == "liver"
                app.MaskLiver(z, :, :) = mask2d;
                app.LiverKeyframes = sort(unique([app.LiverKeyframes, z]));
                voxCm3 = nnz(mask2d) * prod(app.Study.spacingXYZmm) / 1000;
                app.setStatus(sprintf( ...
                    "Manual liver SAVED: slice %d (%d px / %.2f cm^2). %d keyframes total. " + ...
                    "Move to another slice and draw again, then press Interpolate.", ...
                    z, nnz(mask2d), voxCm3 * 10 / app.Study.spacingXYZmm(3), ...
                    numel(app.LiverKeyframes)));
            else
                % Trust the user's contour. We DO NOT clip to the liver
                % mask: the liver mask may be incomplete (semi-auto seed
                % rarely matches manual lesion shapes 1:1), and clipping
                % corrupts SDF interpolation between keyframes.
                app.MaskLesion(z, :, :) = squeeze(app.MaskLesion(z, :, :)) | mask2d;
                app.LesionKeyframes = sort(unique([app.LesionKeyframes, z]));

                area2d = nnz(mask2d) * app.Study.spacingXYZmm(1) * ...
                    app.Study.spacingXYZmm(2) / 100;
                if any(app.MaskLiver, "all")
                    liverHere = squeeze(app.MaskLiver(z, :, :));
                    fracIn = nnz(mask2d & liverHere) / max(nnz(mask2d), 1);
                    if fracIn < 0.5
                        app.setStatus(sprintf( ...
                            "Manual lesion SAVED: slice %d (%d px / %.2f cm^2, %.0f%% inside liver mask). %d keyframes total.", ...
                            z, nnz(mask2d), area2d, 100 * fracIn, numel(app.LesionKeyframes)));
                    else
                        app.setStatus(sprintf( ...
                            "Manual lesion SAVED: slice %d (%d px / %.2f cm^2). %d keyframes total.", ...
                            z, nnz(mask2d), area2d, numel(app.LesionKeyframes)));
                    end
                else
                    app.setStatus(sprintf( ...
                        "Manual lesion SAVED: slice %d (%d px / %.2f cm^2). %d keyframes total.", ...
                        z, nnz(mask2d), area2d, numel(app.LesionKeyframes)));
                end
            end

            app.renderSlice();
            app.updateMetrics();
        end

        function onInterpolateMasks(app)
            % Fill missing slices and extrapolate from keyframes.
            if isempty(fieldnames(app.Study))
                return;
            end
            didLiver = false;
            didLesion = false;
            
            if numel(app.LiverKeyframes) >= 2
                app.MaskLiver = kwod.interpolateKeyframes( ...
                    app.MaskLiver, app.LiverKeyframes, 'target', "liver");
                didLiver = true;
            end
            if numel(app.LesionKeyframes) >= 2
                app.MaskLesion = kwod.interpolateKeyframes( ...
                    app.MaskLesion, app.LesionKeyframes, 'target', "lesion", ...
                    'liverKeyframes', app.LiverKeyframes); 
                didLesion = true;
            end
            
            if ~didLiver && ~didLesion
                uialert(app.Fig, ...
                    "Need at least 2 manual keyframes (liver or lesion).", ...
                    "Not enough keyframes");
                return;
            end
            
            app.renderSlice();
            app.updateMetrics();
            
            parts = strings(0, 1);
            if didLiver
                parts(end + 1, 1) = sprintf("liver: %d->%d", ...
                    min(app.LiverKeyframes), max(app.LiverKeyframes));
            end
            if didLesion
                parts(end + 1, 1) = sprintf("lesion: %d->%d", ...
                    min(app.LesionKeyframes), max(app.LesionKeyframes));
            end
            app.setStatus("Interpolated & Extrapolated " + strjoin(parts, ", ") + ".");
        end

        % ================ Measurements =================================

        function onAddRuler(app)
            if isempty(fieldnames(app.Study))
                uialert(app.Fig, "Load a study first.", "No study");
                return;
            end
            % manual-only
            app.setStatus("Ruler: click and drag, then double-click to finish.");
            drawnow;

            try
                roi = drawline(app.Ax, ...
                    "Color", app.RulerColor, ...
                    "LineWidth", 2);
            catch ex
                app.setStatus("Ruler cancelled.");
                return;
            end

            if isempty(roi) || ~isvalid(roi) || ...
                    isempty(roi.Position) || size(roi.Position, 1) < 2 || ...
                    norm(diff(roi.Position, 1, 1)) < 1
                if ~isempty(roi) && isvalid(roi)
                    delete(roi);
                end
                app.setStatus("Ruler cancelled.");
                return;
            end

            pts = roi.Position;
            delete(roi);

            info = kwod.measureLine(pts, app.Study.spacingXYZmm);

            m = struct( ...
                "type", "line", ...
                "slice", app.CurrentZ, ...
                "points", pts, ...
                "lengthMm", info.lengthMm, ...
                "midpoint", info.midpoint);
            app.Measurements{end + 1} = m;

            app.renderSlice();
            app.updateMetrics();
            app.setStatus(sprintf("Ruler: %.1f mm (slice %d).", ...
                info.lengthMm, app.CurrentZ));
        end

        function onAddCircle(app)
            if isempty(fieldnames(app.Study))
                uialert(app.Fig, "Load a study first.", "No study");
                return;
            end
            % manual-only
            app.setStatus("Circle ROI: PRESS LMB at the center, DRAG to set radius, RELEASE.");
            drawnow;

            roi = [];
            try
                roi = drawcircle(app.Ax, ...
                    "Color", app.RoiColor, ...
                    "LineWidth", 2.5);
            catch ex
                app.setStatus(sprintf("Circle ROI failed: %s", ex.message));
                return;
            end

            if isempty(roi) || ~isvalid(roi)
                app.setStatus("Circle ROI cancelled.");
                return;
            end
            if roi.Radius < 1.5
                delete(roi);
                app.setStatus("Circle ROI too small (radius < 1.5 px) - try again with a larger drag.");
                return;
            end

            center = roi.Center;
            radiusPx = roi.Radius;

            % createMask in uifigure/webaxes is more reliable when the
            % image handle is passed explicitly.
            mask2d = [];
            try
                if ~isempty(app.ImgHandle) && isvalid(app.ImgHandle)
                    mask2d = createMask(roi, app.ImgHandle);
                else
                    mask2d = createMask(roi);
                end
            catch ex
                mask2d = [];
                app.setStatus(sprintf("createMask failed: %s", ex.message));
            end
            delete(roi);

            sz = app.Study.shapeZYX;
            if isempty(mask2d) || ~any(mask2d, "all") || ...
                    ~isequal(size(mask2d), [sz(2), sz(3)])
                % Fallback: synthesize the mask analytically from
                % center+radius. Works regardless of webaxes quirks.
                [Xg, Yg] = meshgrid(1:sz(3), 1:sz(2));
                mask2d = (Xg - center(1)).^2 + (Yg - center(2)).^2 <= radiusPx ^ 2;
            end

            if ~any(mask2d, "all")
                app.setStatus("Circle ROI mask is empty - cannot compute statistics.");
                return;
            end

            sl = squeeze(app.Study.volumeZYX(app.CurrentZ, :, :));
            info = kwod.measureCircle(sl, mask2d, center, radiusPx, ...
                app.Study.spacingXYZmm);

            m = struct( ...
                "type", "circle", ...
                "slice", app.CurrentZ, ...
                "center", center, ...
                "radiusPx", radiusPx, ...
                "diameterMm", info.diameterMm, ...
                "areaCm2", info.areaCm2, ...
                "meanHU", info.meanHU, ...
                "stdHU", info.stdHU, ...
                "minHU", info.minHU, ...
                "maxHU", info.maxHU);
            app.Measurements{end + 1} = m;

            app.renderSlice();
            app.updateMetrics();
            app.setStatus(sprintf( ...
                "ROI saved: %.2f cm^2 | HU mean %.0f +/- %.0f | min %.0f / max %.0f (slice %d).", ...
                info.areaCm2, info.meanHU, info.stdHU, ...
                info.minHU, info.maxHU, app.CurrentZ));
        end

        function onClearMeasurements(app)
            app.Measurements = {};
            app.renderSlice();
            app.updateMetrics();
            app.setStatus("Measurements cleared.");
        end

        % ================ Reference (IRCAD ground truth) ===============

        function onLoadReference(app)
            if isempty(fieldnames(app.Study))
                uialert(app.Fig, "Load a CT study first.", "No study");
                return;
            end

            folder = uigetdir("", ...
                "Select MASKS_DICOM folder (IRCAD ground truth)");
            if isequal(folder, 0)
                return;
            end

            app.setStatus("Loading reference masks...");
            drawnow;

            try
                ref = kwod.loadReferenceMasks(folder, app.Study.shapeZYX);
            catch ex
                uialert(app.Fig, ex.message, "Reference load error");
                app.setStatus("Reference load failed.");
                return;
            end

            app.RefLiver = ref.liver;
            app.RefLesion = ref.lesion;
            app.RefInfo = ref;

            app.renderSlice();
            app.updateMetrics();

            n = numel(ref.lesionFolders);
            app.setStatus(sprintf( ...
                "Reference loaded: liver='%s', %d lesion subfolder(s).", ...
                ref.liverFolder, n));
        end

        % ================ Slice / rendering ============================

        function onSliceChange(app, val)
            if isempty(fieldnames(app.Study))
                return;
            end
            app.CurrentZ = max(1, min(app.Study.shapeZYX(1), round(val)));
            if ~isempty(app.SliceSlider)
                app.SliceSlider.Value = app.CurrentZ;
            end
            app.updateSliceLabel();
            app.renderSlice();
        end

        function onSliceStep(app, delta)
            % +/- step in slices. delta is signed integer (negative = back).
            if isempty(fieldnames(app.Study))
                return;
            end
            app.onSliceChange(app.CurrentZ + delta);
        end

        function onKeyPress(app, evt)
            % Keyboard shortcuts for slice navigation:
            %   Left  / Right       : -1 / +1 slice
            %   PageUp / PageDown   : -10 / +10 slices  (PageUp = back)
            %   Home / End          : first / last slice
            if isempty(fieldnames(app.Study))
                return;
            end
            switch evt.Key
                case "leftarrow"
                    app.onSliceStep(-1);
                case "rightarrow"
                    app.onSliceStep(1);
                case "pageup"
                    app.onSliceStep(-10);
                case "pagedown"
                    app.onSliceStep(10);
                case "home"
                    app.onSliceChange(1);
                case "end"
                    app.onSliceChange(app.Study.shapeZYX(1));
            end
        end

        function renderSlice(app)
            if isempty(fieldnames(app.Study))
                cla(app.Ax);
                app.ImgHandle = [];
                return;
            end

            z = app.CurrentZ;
            vol = app.Study.volumeZYX;
            sl = squeeze(vol(z, :, :));

            wl = app.WindowLevel;
            ww = max(1.0, app.WindowWidth);
            lo = wl - ww / 2;
            hi = wl + ww / 2;
            img = (min(max(sl, lo), hi) - lo) ./ (hi - lo);

            cla(app.Ax);
            app.ImgHandle = imagesc(app.Ax, img);
            colormap(app.Ax, gray(256));
            axis(app.Ax, "image");
            app.Ax.YDir = "reverse";
            app.Ax.XTick = [];
            app.Ax.YTick = [];
            app.Ax.CLim = [0, 1];
            hold(app.Ax, "on");

            app.ImgHandle.PickableParts = "none";
            app.ImgHandle.HitTest = "off";

            showLiver = ~isempty(app.ShowLiverCb) && app.ShowLiverCb.Value;
            showLesion = ~isempty(app.ShowLesionCb) && app.ShowLesionCb.Value;
            showRef = ~isempty(app.ShowRefCb) && app.ShowRefCb.Value;

            if showLiver && ~isempty(app.MaskLiver) && z <= size(app.MaskLiver, 1)
                overlayMask(app.Ax, squeeze(app.MaskLiver(z, :, :)), ...
                    app.LiverColor, app.LiverAlpha);
            end
            if showLesion && ~isempty(app.MaskLesion) && z <= size(app.MaskLesion, 1)
                overlayMask(app.Ax, squeeze(app.MaskLesion(z, :, :)), ...
                    app.LesionColor, app.LesionAlpha);
            end

            if showRef
                if ~isempty(app.RefLiver) && z <= size(app.RefLiver, 1)
                    overlayContour(app.Ax, squeeze(app.RefLiver(z, :, :)), ...
                        app.RefLiverColor);
                end
                if ~isempty(app.RefLesion) && z <= size(app.RefLesion, 1)
                    overlayContour(app.Ax, squeeze(app.RefLesion(z, :, :)), ...
                        app.RefLesionColor);
                end
            end

            app.drawMeasurementsForSlice(z);

            hold(app.Ax, "off");
        end

        function drawMeasurementsForSlice(app, z)
            lineCounter = 0;
            circleCounter = 0;
            for i = 1:numel(app.Measurements)
                m = app.Measurements{i};
                if m.slice ~= z
                    if m.type == "line"
                        lineCounter = lineCounter + 1;
                    elseif m.type == "circle"
                        circleCounter = circleCounter + 1;
                    end
                    continue;
                end

                if m.type == "line"
                    lineCounter = lineCounter + 1;
                    plot(app.Ax, m.points(:, 1), m.points(:, 2), "-", ...
                        "Color", app.RulerColor, ...
                        "LineWidth", app.RulerLineWidth);
                    plot(app.Ax, m.points(:, 1), m.points(:, 2), "o", ...
                        "Color", app.RulerColor, ...
                        "MarkerFaceColor", app.RulerColor, ...
                        "MarkerSize", 7);

                    label = sprintf("L%d  %.1f mm", lineCounter, m.lengthMm);
                    drawHaloLabel(app.Ax, ...
                        m.midpoint(1), m.midpoint(2) - 8, ...
                        label, app.RulerColor, app.LabelFontSize);

                elseif m.type == "circle"
                    circleCounter = circleCounter + 1;
                    theta = linspace(0, 2 * pi, 96);
                    cx = m.center(1) + m.radiusPx * cos(theta);
                    cy = m.center(2) + m.radiusPx * sin(theta);
                    plot(app.Ax, cx, cy, "-", ...
                        "Color", app.RoiColor, ...
                        "LineWidth", app.RoiLineWidth);
                    plot(app.Ax, m.center(1), m.center(2), "+", ...
                        "Color", app.RoiColor, ...
                        "LineWidth", 2, ...
                        "MarkerSize", 12);

                    label = sprintf("C%d  %.2f cm^2  HU %.0f", ...
                        circleCounter, m.areaCm2, m.meanHU);
                    drawHaloLabel(app.Ax, ...
                        m.center(1), m.center(2) - m.radiusPx - 6, ...
                        label, app.RoiColor, app.LabelFontSize);
                end
            end
        end

        % ================ Metrics ======================================

        function updateMetrics(app)
            if isempty(fieldnames(app.Study))
                app.MetricsArea.Value = {'No study loaded.'};
                return;
            end

            metrics = kwod.computeVolumes(app.MaskLiver, app.MaskLesion, ...
                app.Study.spacingXYZmm);

            lines = strings(0, 1);
            lines(end + 1, 1) = sprintf("Source: %s", app.Study.filePath);
            lines(end + 1, 1) = sprintf("Shape [Z,Y,X]: [%d, %d, %d]", ...
                app.Study.shapeZYX(1), app.Study.shapeZYX(2), app.Study.shapeZYX(3));
            lines(end + 1, 1) = sprintf("Spacing [dx,dy,dz] mm: [%.3f, %.3f, %.3f]", ...
                app.Study.spacingXYZmm(1), app.Study.spacingXYZmm(2), app.Study.spacingXYZmm(3));
            lines(end + 1, 1) = sprintf("Voxel volume: %.5f cm^3", metrics.voxelVolumeCm3);

            if isfield(metrics, "liverVoxels") && metrics.liverVoxels > 0
                lines(end + 1, 1) = sprintf("Liver: %d voxels | %.2f cm^3", ...
                    metrics.liverVoxels, metrics.liverVolumeCm3);
            else
                lines(end + 1, 1) = "Liver: not segmented (press 'Seed liver' and click)";
            end
            if isfield(metrics, "lesionVoxels") && metrics.lesionVoxels > 0
                lines(end + 1, 1) = sprintf("Lesion: %d voxels | %.2f cm^3", ...
                    metrics.lesionVoxels, metrics.lesionVolumeCm3);
            else
                lines(end + 1, 1) = "Lesion: not segmented";
            end

            if ~isempty(app.LiverKeyframes)
                lines(end + 1, 1) = sprintf("Liver keyframes (%d): %s", ...
                    numel(app.LiverKeyframes), ...
                    strjoin(string(app.LiverKeyframes), ", "));
            end
            if ~isempty(app.LesionKeyframes)
                lines(end + 1, 1) = sprintf("Lesion keyframes (%d): %s", ...
                    numel(app.LesionKeyframes), ...
                    strjoin(string(app.LesionKeyframes), ", "));
            end
            if isfield(metrics, "lesionPercentOfLiver") && ...
                    metrics.liverVoxels > 0 && metrics.lesionVoxels > 0
                lines(end + 1, 1) = sprintf("Lesion involvement: %.2f %% of liver", ...
                    metrics.lesionPercentOfLiver);
            end

            % --- Reference / Dice ----------------------------------------
            if ~isempty(app.RefLiver) || ~isempty(app.RefLesion)
                vox = metrics.voxelVolumeCm3;
                lines(end + 1, 1) = "--- Reference (IRCAD) ---";
                if ~isempty(app.RefInfo) && isfield(app.RefInfo, "liverFolder")
                    lines(end + 1, 1) = sprintf("Reference liver: %s", ...
                        app.RefInfo.liverFolder);
                end
                if ~isempty(app.RefInfo) && isfield(app.RefInfo, "lesionFolders") && ...
                        ~isempty(app.RefInfo.lesionFolders)
                    lines(end + 1, 1) = sprintf("Reference lesions: %s", ...
                        strjoin(app.RefInfo.lesionFolders, ", "));
                end
                if ~isempty(app.RefLiver) && any(app.RefLiver, "all")
                    refLiverVoxels = nnz(app.RefLiver);
                    refLiverCm3 = refLiverVoxels * vox;
                    lines(end + 1, 1) = sprintf( ...
                        "Ref liver volume: %.2f cm^3 (%d voxels)", ...
                        refLiverCm3, refLiverVoxels);
                    if any(app.MaskLiver, "all")
                        d = kwod.dice(app.MaskLiver, app.RefLiver);
                        diff = metrics.liverVolumeCm3 - refLiverCm3;
                        diffPct = 100 * diff / max(refLiverCm3, eps);
                        lines(end + 1, 1) = sprintf( ...
                            "Dice (liver):  %.3f   |   dV: %+.2f cm^3 (%+.1f %%)", ...
                            d, diff, diffPct);
                    end
                end
                if ~isempty(app.RefLesion) && any(app.RefLesion, "all")
                    refLesionVoxels = nnz(app.RefLesion);
                    refLesionCm3 = refLesionVoxels * vox;
                    lines(end + 1, 1) = sprintf( ...
                        "Ref lesion volume: %.2f cm^3 (%d voxels)", ...
                        refLesionCm3, refLesionVoxels);
                    if any(app.MaskLesion, "all")
                        d = kwod.dice(app.MaskLesion, app.RefLesion);
                        diff = metrics.lesionVolumeCm3 - refLesionCm3;
                        diffPct = 100 * diff / max(refLesionCm3, eps);
                        lines(end + 1, 1) = sprintf( ...
                            "Dice (lesion): %.3f   |   dV: %+.2f cm^3 (%+.1f %%)", ...
                            d, diff, diffPct);
                    end
                end
            end

            % --- Measurements --------------------------------------------
            if ~isempty(app.Measurements)
                lines(end + 1, 1) = "--- Measurements ---";
                lc = 0; cc = 0;
                for i = 1:numel(app.Measurements)
                    m = app.Measurements{i};
                    if m.type == "line"
                        lc = lc + 1;
                        lines(end + 1, 1) = sprintf( ...
                            "L%d (slice %d): %.1f mm", lc, m.slice, m.lengthMm); %#ok<AGROW>
                    elseif m.type == "circle"
                        cc = cc + 1;
                        lines(end + 1, 1) = sprintf( ...
                            "C%d (slice %d): %.2f cm^2 | diam %.1f mm | HU %.0f +/- %.0f", ...
                            cc, m.slice, m.areaCm2, m.diameterMm, ...
                            m.meanHU, m.stdHU); %#ok<AGROW>
                    end
                end
            end

            app.MetricsArea.Value = cellstr(lines);
        end

        function updateSliceLabel(app)
            if isempty(fieldnames(app.Study))
                app.SliceLabel.Text = "-";
                return;
            end
            mark = "";
            if ismember(app.CurrentZ, app.LiverKeyframes)
                mark = mark + "  *L";
            end
            if ismember(app.CurrentZ, app.LesionKeyframes)
                mark = mark + "  *E";
            end
            app.SliceLabel.Text = sprintf("%d / %d%s", ...
                app.CurrentZ, app.Study.shapeZYX(1), mark);
        end

        function setStatus(app, txt)
            app.StatusLabel.Text = txt;
        end
    end
end

function overlayMask(ax, mask2d, colorRGB, alphaValue)
    if ~any(mask2d, "all")
        return;
    end
    [h, w] = size(mask2d);
    c = cat(3, ...
        ones(h, w) * colorRGB(1), ...
        ones(h, w) * colorRGB(2), ...
        ones(h, w) * colorRGB(3));
    hImg = image(ax, c);
    hImg.AlphaData = double(mask2d) * alphaValue;
    hImg.HitTest = "off";
    hImg.PickableParts = "none";
end

function overlayContour(ax, mask2d, colorRGB)
    if ~any(mask2d, "all")
        return;
    end
    % 2-pixel-wide contour for visibility on grayscale CT
    edges = mask2d & ~imerode(mask2d, strel("disk", 2));
    if ~any(edges, "all")
        return;
    end
    [h, w] = size(edges);
    c = cat(3, ...
        ones(h, w) * colorRGB(1), ...
        ones(h, w) * colorRGB(2), ...
        ones(h, w) * colorRGB(3));
    hImg = image(ax, c);
    hImg.AlphaData = double(edges);
    hImg.HitTest = "off";
    hImg.PickableParts = "none";
end

function drawHaloLabel(ax, x, y, str, fillColor, fontSize)
% Render text with a 1-px black halo for guaranteed readability on top
% of any background. This is more robust across MATLAB versions and
% renderers than `BackgroundColor + EdgeColor` on text() in webaxes.
    haloOffsets = [-1, 0; 1, 0; 0, -1; 0, 1; -1, -1; 1, -1; -1, 1; 1, 1];
    for k = 1:size(haloOffsets, 1)
        text(ax, x + haloOffsets(k, 1), y + haloOffsets(k, 2), str, ...
            "Color", [0, 0, 0], ...
            "FontWeight", "bold", ...
            "FontSize", fontSize, ...
            "HorizontalAlignment", "center", ...
            "VerticalAlignment", "bottom", ...
            "Clipping", "on", ...
            "PickableParts", "none", ...
            "HitTest", "off");
    end
    text(ax, x, y, str, ...
        "Color", fillColor, ...
        "FontWeight", "bold", ...
        "FontSize", fontSize, ...
        "HorizontalAlignment", "center", ...
        "VerticalAlignment", "bottom", ...
        "Clipping", "on", ...
        "PickableParts", "none", ...
        "HitTest", "off");
end
