function distanceTable = cellDistances(compiledData, outputFolder, options)
% CELLDISTANCES Calculate distance metrics for each tracked cell from
% compiled tracking data produced by compileResultsFromCSV.
%
% For each cell track, computes cumulative path length, average
% frame-to-frame displacement, net displacement, and the directional 
% persistence ratio. Results are returned as a table and optionally saved.
%
% INPUT:
% 
% Required:
%   compiledData: (table)
%       Tracking table produced by compileResultsCSV. Must contain
%       columns X, Y, Z, T.
%
% Optional:
%   outputFolder: (char | string, default: "" (no file is written))
%       Directory where the output file will be saved. Created automatically
%       if it does not exist.
%
%   options
%
%       OutputFilename: (char | string, default: "Distance_Results.csv")
%           Name of the output file.
%
%       Logs: (logical, default: true)
%           Print progress messages to the command window.
%
% OUTPUT
%   distanceTable: (table)
%       One row per tracked cell. Columns:
%           Cell - 1-based cell index
%           AvgFrameDistance - mean step-to-step displacement
%           CumulativeDistance - total path length across all frames
%           RelativeDisplacement - distance from first to last position
%           DirectionalPersistence - efficiency of motion toward end point

    arguments
        compiledData (:,:) table
        outputFolder (1,1) string = ""
        options.OutputFilename (1,1) string = "Distance_Results.csv"
        options.Logs (1,1) logical = true
    end

    requiredCols = {'X', 'Y', 'Z', 'T'};
    missingCols = requiredCols(~ismember(requiredCols, compiledData.Properties.VariableNames));
    if ~isempty(missingCols)
        error('cellDistances:missingColumns', ...
              'compiledData is missing required column(s): %s', ...
              strjoin(missingCols, ', '));
    end

    cellTracks = segmentTracks(compiledData);
    numCells = numel(cellTracks);

    if numCells == 0
        warning('cellDistances:noTracks', ...
                'No cell tracks found in compiledData.');
        distanceTable = table();
        return
    end

    cumulativeDistances = zeros(numCells, 1);
    avgFrameDistances = zeros(numCells, 1);
    relativeDisplacements = zeros(numCells, 1);

    % Compute distance metrics for each track
    for k = 1:numCells
        track = cellTracks{k};
        nFrames = height(track);

        % Euclidean distances between consecutive frames
        frameDistances = zeros(nFrames - 1, 1);
        for j = 1:(nFrames - 1)
            dx = track.X(j+1) - track.X(j);
            dy = track.Y(j+1) - track.Y(j);
            dz = track.Z(j+1) - track.Z(j);
            frameDistances(j) = sqrt(dx^2 + dy^2 + dz^2);
        end

        % Total path length (sum of all step distances)
        cumulativeDistances(k) = sum(frameDistances);

        % Average step size across all consecutive frame pairs
        avgFrameDistances(k) = mean(frameDistances);

        % Net displacement: straight-line distance from first to last point
        dx = track.X(end) - track.X(1);
        dy = track.Y(end) - track.Y(1);
        dz = track.Z(end) - track.Z(1);
        relativeDisplacements(k) = sqrt(dx^2 + dy^2 + dz^2);
    end

    % Directional Persistence = net displacement / total path length.
    % ** Will produce NaN if CumulativeDistance == 0. **
    directionalPersistence = relativeDisplacements ./ cumulativeDistances;
 
    % Assemble output table
    cellIndex = (1:numCells)';
    distanceTable = table( ...
        cellIndex, ...
        num2cell(avgFrameDistances), ...
        num2cell(cumulativeDistances), ...
        num2cell(relativeDisplacements), ...
        num2cell(directionalPersistence), ...
        'VariableNames', { ...
            'Cell', ...
            'AvgFrameDistance', ...
            'CumulativeDistance', ...
            'RelativeDisplacement', ...
            'DirectionalPersistence'} );

    % Optionally write to disk
    if outputFolder ~= ""
        if ~isfolder(outputFolder)
            mkdir(outputFolder);
        end
        outputPath = fullfile(outputFolder, options.OutputFilename);
        writetable(distanceTable, outputPath);
        if options.Logs
            fprintf('[distances]  Saved %d cell(s) to: %s\n', numCells, outputPath);
        end
    end

    if options.Logs
        fprintf('[distances]  Done. Processed %d cell track(s).\n', numCells);
    end

end
