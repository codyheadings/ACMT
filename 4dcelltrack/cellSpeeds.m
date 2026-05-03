function speedTable = cellSpeeds(compiledData, outputFolder, options)
% CELLSPEEDS Calculate speed metrics for each tracked cell from
% compiled tracking data produced by compileResultsCSV.
%
% For each cell track, computes average speed, cumulative speed, and 
% speed variance over the full period, as well as the first and 
% second halves independently. Results are returned as a table and 
% optionally saved to a file.
%
% INPUT:
%
% Required:
%   compiledData: (table)
%       Tracking table produced by compileResultsFromCSV. Must contain
%       columns X, Y, Z, T. All tracks must share the same time step.
%
% Optional:
%   outputFolder: (char | string, default: "" (no file is written))
%       Directory where the output file will be saved. Created automatically
%       if it does not exist.
%
%   options
%
%       OutputFilename: (char | string, default: "Speed_Results.csv")
%           Name of the output file.
%
%       Logs: (logical, default: true)
%           Print progress messages to the command window.
%
% OUTPUT
%   speedTable (table)
%       One row per tracked cell. Columns:
%           Cell - 1-based index
%           AvgCellSpeed - mean speed
%           CumulativeCellSpeed - speed sum
%           VarianceEntirePeriod - speed variance across all frames
%           VarianceFirstHalf - speed variance over the first half
%           VarianceLastHalf - speed variance over the second half

    arguments
        compiledData (:,:) table
        outputFolder (1,1) string = ""
        options.OutputFilename (1,1) string = "Speed_Results.csv"
        options.Logs (1,1) logical = true
    end

    requiredCols = {'X', 'Y', 'Z', 'T'};
    missingCols = requiredCols(~ismember(requiredCols, compiledData.Properties.VariableNames));
    if ~isempty(missingCols)
        error('cellSpeeds:missingColumns', ...
              'compiledData is missing required column(s): %s', ...
              strjoin(missingCols, ', '));
    end

    % Calculate frame interval and total frame count from T column.
    % Assumed uniform across all tracks.
    frameInterval = compiledData.T(2) - compiledData.T(1);
    numFrames = (max(compiledData.T) / frameInterval) + 1;

    if frameInterval <= 0
        error('cellSpeeds:invalidFrameInterval', ...
              'Frame interval T(2)-T(1) is <= 0. Check compiledData.T.');
    end

    cellTracks = segmentTracks(compiledData);
    numCells = numel(cellTracks);

    if numCells == 0
        warning('cellSpeeds:noTracks', ...
                'No cell tracks found in compiledData.');
        speedTable = table();
        return
    end

    avgSpeeds = zeros(numCells, 1);
    totalSpeeds = zeros(numCells, 1);
    variances = cell(numCells, 3);

    firstHalfEnd = floor(numFrames / 2);
    secondHalfStart = firstHalfEnd + 1;

    % Compute speed metrics for each track
    for k = 1:numCells
        track = cellTracks{k};
        nFrames = height(track);

        % Euclidean distance divided by frame interval
        trackSpeeds = zeros(nFrames - 1, 1);
        for j = 1:(nFrames - 1)
            dx = track.X(j+1) - track.X(j);
            dy = track.Y(j+1) - track.Y(j);
            dz = track.Z(j+1) - track.Z(j);
            distance = sqrt(dx^2 + dy^2 + dz^2);
            trackSpeeds(j) = distance / frameInterval;
        end

        % Average and cumulative speed
        avgSpeeds(k) = mean(trackSpeeds);
        totalSpeeds(k) = sum(trackSpeeds);

        % Variance over full period, first half, and second half
        variances{k, 1} = var(trackSpeeds);
        variances{k, 2} = var(trackSpeeds(1:firstHalfEnd));
        variances{k, 3} = var(trackSpeeds(secondHalfStart:end));
    end

    cellIndex = (1:numCells)';
    varianceEntirePeriod = cell2mat(variances(:, 1));
    varianceFirstHalf = cell2mat(variances(:, 2));
    varianceLastHalf = cell2mat(variances(:, 3));

    speedTable = table( ...
        cellIndex, ...
        avgSpeeds, ...
        totalSpeeds, ...
        varianceEntirePeriod, ...
        varianceFirstHalf, ...
        varianceLastHalf, ...
        'VariableNames', { ...
            'Cell', ...
            'AvgCellSpeed', ...
            'CumulativeCellSpeed', ...
            'VarianceEntirePeriod', ...
            'VarianceFirstHalf', ...
            'VarianceLastHalf'} );

    if outputFolder ~= ""
        if ~isfolder(outputFolder)
            mkdir(outputFolder);
        end
        outputPath = fullfile(outputFolder, options.OutputFilename);
        writetable(speedTable, outputPath);
        if options.Logs
            fprintf('[speeds]  Saved %d cell(s) to: %s\n', numCells, outputPath);
        end
    end

    if options.Logs
        fprintf('[speeds]  Done. Processed %d cell track(s).\n', numCells);
    end

end
