function filteredTracks = filterDuplicateTracks(aggregatedTracks, options)
% FILTERDUPLICATETRACKS Detect and remove duplicate cell tracks from a
% compiled tracking table produced by compileResultsFromCSV.
%
% Two tracks are considered duplicates if, over their shared timepoints,
% their XY distance stays within XYTolerance AND their Z distance stays
% within ZTolerance for at least OverlapPercent of those timepoints.
% When a duplicate pair is found, the first track (by row order) is kept
% and the second is removed.
%
% Tracks from different groups are never compared against each other.
%
% INPUTS:
%
% Required:
%   aggregatedTracks (table | string | char)
%       Tracking table from aggregateTrackingResults, provided as file path
%       or table. Must contain columns:
%           GroupingCols, Num, TrackerName, X, Y, Z, T. Grouping columns 
%           must precede Num column to be correctly detected.
%
% Optional:
%   options
%
%       XYTolerance (double, default: 5)
%           Max XY distance between two tracks at shared
%           timepoints for them to be considered duplicates.
%
%       ZTolerance (double, default: 40)
%           Max Z distance between two tracks at shared
%           timepoints for them to be considered duplicates.
%
%       OverlapPercent (double, default: 0.75)
%           Min fraction of shared timepoints at which XY and Z tolerances
%           must be satisfied for tracks to be flagged as duplicates.
%           Must be in (0, 1].
%
%       OutputPath (char | string, default: "" (no file written))
%           If provided, a two-sheet Excel report is written to this path:
%               KeptTracks - summary of all tracks that were retained
%               RemovedTracks - summary of removed tracks
%
%       Logs (logical, default: true)
%           Print progress messages to the command window.
%
% OUTPUT:
%
%   filteredData (table)
%       Subset of aggregatedTracks with duplicate track rows removed. The
%       table structure is identical to the input so it can be passed
%       directly to analyzeByGroup or other functions.

    arguments
        aggregatedTracks {mustBeA(aggregatedTracks,["table","string","char"])}
        options.XYTolerance (1,1) double = 5
        options.ZTolerance (1,1) double = 40
        options.OverlapPercent (1,1) double = 0.75
        options.OutputPath (1,1) string = ""
        options.Logs (1,1) logical = true
    end

    if isstring(aggregatedTracks) || ischar(aggregatedTracks)
        if ~isfile(aggregatedTracks)
            error('filterDuplicateTracks:fileNotFound', ...
                'File not found:\n%s', aggregatedTracks);
        end
        aggregatedTracks = readtable(aggregatedTracks);
    end

    requiredCols = {'X', 'Y', 'Z', 'T'};
    missingCols = requiredCols(~ismember(requiredCols, aggregatedTracks.Properties.VariableNames));
    if ~isempty(missingCols)
        error('filterDuplicateTracks:missingColumns', ...
              'aggregatedTracks is missing required column(s): %s', ...
              strjoin(missingCols, ', '));
    end

    if options.OverlapPercent <= 0 || options.OverlapPercent > 1
        error('filterDuplicateTracks:invalidOverlap', ...
              'OverlapPercent must be in (0, 1]. Got: %g', options.OverlapPercent);
    end

    allCols = aggregatedTracks.Properties.VariableNames;

    % Find the 'Num' column
    numIdx = find(strcmp(allCols, 'Num'), 1);
    
    if isempty(numIdx)
        error('filterDuplicateTracks:missingNumColumn', ...
              'aggregatedTracks must contain a ''Num'' column.');
    end
    
    % Everything before 'Num' is treated as a group column
    condCols = allCols(1:numIdx-1);

    if isempty(condCols)
        if options.Logs
            fprintf('[filter]  No Condition columns found; comparing all tracks as one group.\n');
        end
        groupKeys = {''};
    else
        groupKeys = buildGroupKeys(aggregatedTracks, condCols);
    end

    uniqueGroups = unique(groupKeys, 'stable');

    % segmentTracks returns a cell array of track tables; we also need to
    % know the original row indices so we can mark rows for removal.
    [tracks, trackRowRanges] = segmentTracksWithIndex(aggregatedTracks);
    nTracks = numel(tracks);

    if options.Logs
        fprintf('[filter]  %d track(s) found across %d group(s).\n', ...
                nTracks, numel(uniqueGroups));
    end

    % Assign each track to its group based on its first row's group values
    trackGroups = cell(nTracks, 1);
    for k = 1:nTracks
        firstRow = trackRowRanges(k, 1);
        trackGroups{k} = groupKeys{firstRow};
    end

    % Pairwise duplicate detection within each group
    keepTrack = true(nTracks, 1);

    keptSummary = {};
    removedSummary = {};

    for g = 1:numel(uniqueGroups)
        grpLabel = uniqueGroups{g};
        grpIdx = find(strcmp(trackGroups, grpLabel));
        n = numel(grpIdx);

        if n < 2
            continue
        end

        % All-pairs comparison within the group
        for i = 1:(n - 1)
            ki = grpIdx(i);
            if ~keepTrack(ki), continue, end   % already marked as duplicate

            for j = (i + 1):n
                kj = grpIdx(j);
                if ~keepTrack(kj), continue, end

                overlapFrac = computeOverlap( ...
                    tracks{ki}, tracks{kj}, ...
                    options.XYTolerance, options.ZTolerance);

                if overlapFrac >= options.OverlapPercent
                    % Keep ki, remove kj
                    keepTrack(kj) = false;

                    if options.Logs
                        fprintf('  [duplicate]  Track %d removed (duplicate of track %d, overlap=%.2f)\n', ...
                                kj, ki, overlapFrac);
                    end

                    if options.OutputPath ~= ""
                        removedSummary{end+1} = buildTrackSummaryRow( ...
                            tracks{kj}, kj, ki, condCols, aggregatedTracks, ...
                            trackRowRanges(kj, 1)); %#ok<AGROW>
                    end
                end
            end
        end

        if options.OutputPath ~= ""
            for i = 1:n
                ki = grpIdx(i);
                if keepTrack(ki)
                    keptSummary{end+1} = buildTrackSummaryRow( ...
                        tracks{ki}, ki, NaN, condCols, aggregatedTracks, ...
                        trackRowRanges(ki, 1)); %#ok<AGROW>
                end
            end
        end
    end

    keepRow = false(height(aggregatedTracks), 1);
    for k = 1:nTracks
        if keepTrack(k)
            keepRow(trackRowRanges(k,1):trackRowRanges(k,2)) = true;
        end
    end

    filteredTracks = aggregatedTracks(keepRow, :);

    nRemoved = sum(~keepTrack);
    nKept = sum(keepTrack);

    if options.Logs
        fprintf('[filter]  Kept %d track(s), removed %d duplicate(s).\n', ...
                nKept, nRemoved);
    end

    if options.OutputPath ~= ""
        writeReport(options.OutputPath, keptSummary, removedSummary, condCols);
        if options.Logs
            fprintf('[filter]  Report saved -> %s\n', options.OutputPath);
        end
    end

end


% LOCAL HELPERS

function [tracks, rowRanges] = segmentTracksWithIndex(data)
% SEGMENTTRACKSWITINDEX Wrapper around segmentTracks that also returns the
% start and end row index of each track within the original table.

    tracks = segmentTracks(data);
    nTracks = numel(tracks);
    rowRanges = zeros(nTracks, 2);

    cursor = 1;
    for k = 1:nTracks
        len = height(tracks{k});
        rowRanges(k, :) = [cursor, cursor + len - 1];
        cursor = cursor + len;
    end
end


function keys = buildGroupKeys(data, condCols)
% BUILDGROUPKEYS Build a cell array of group key strings, one per row.

    nRows = height(data);
    keys = cell(nRows, 1);

    for r = 1:nRows
        parts = cell(1, numel(condCols));
        for c = 1:numel(condCols)
            v = data.(condCols{c})(r);
            if iscell(v), parts{c} = v{1};
            else, parts{c} = char(v);
            end
        end
        keys{r} = strjoin(parts, '|');
    end
end


function overlapFrac = computeOverlap(trackI, trackJ, xyTol, zTol)
% COMPUTEOVERLAP Compare two tracks over their shared timepoints.
%
% Returns the fraction of shared timepoints at which both XY and Z
% distances are within their respective tolerances. Tracks of different
% lengths are aligned on T values; only timepoints present in both are
% compared. Returns 0 if there are no shared timepoints.

    tI = trackI.T;
    tJ = trackJ.T;

    % Find shared timepoints
    sharedT = intersect(tI, tJ);

    if isempty(sharedT)
        overlapFrac = 0;
        return
    end

    % Align rows to shared timepoints
    [~, idxI] = ismember(sharedT, tI);
    [~, idxJ] = ismember(sharedT, tJ);

    xyzI = [trackI.X(idxI), trackI.Y(idxI), trackI.Z(idxI)];
    xyzJ = [trackJ.X(idxJ), trackJ.Y(idxJ), trackJ.Z(idxJ)];

    % Per-timepoint distances
    distXY = sqrt((xyzI(:,1) - xyzJ(:,1)).^2 + (xyzI(:,2) - xyzJ(:,2)).^2);
    distZ = abs(xyzI(:,3) - xyzJ(:,3));

    isClose = (distXY <= xyTol) & (distZ <= zTol);

    maxLen = max(numel(tI), numel(tJ));
    overlapFrac = sum(isClose) / maxLen;
end


function row = buildTrackSummaryRow(track, trackIdx, duplicateOf, condCols, fullData, firstRowIdx)
% BUILDTRACKSUMMARYROW Build one row for the export report as a cell array.

    condVals = cell(1, numel(condCols));
    for c = 1:numel(condCols)
        v = fullData.(condCols{c})(firstRowIdx);
        if iscell(v), condVals{c} = v{1};
        else,         condVals{c} = char(v);
        end
    end

    if ismember('TrackerName', fullData.Properties.VariableNames)
        tn = fullData.TrackerName(firstRowIdx);
        if iscell(tn), trackerName = tn{1};
        else, trackerName = char(tn);
        end
    else
        trackerName = '';
    end

    startX = track.X(1);
    startY = track.Y(1);
    startZ = track.Z(1);

    row = [condVals, {trackerName, trackIdx, duplicateOf, startX, startY, startZ}];
end


function writeReport(outputPath, keptSummary, removedSummary, condCols)
% WRITEREPORT Write kept and removed track summaries to an Excel file.

    metaCols = [condCols, {'TrackerName', 'Index', 'DuplicateOf', 'StartX', 'StartY', 'StartZ'}];
    removeCols = [condCols, {'TrackerName', 'Index', 'DuplicateOf', 'StartX', 'StartY', 'StartZ'}];

    outDir = fileparts(outputPath);
    if outDir ~= "" && ~isfolder(outDir)
        mkdir(outDir);
    end

    if ~isempty(keptSummary)
        keptTable = cell2table(vertcat(keptSummary{:}), 'VariableNames', metaCols);
    else
        keptTable = cell2table(cell(0, numel(metaCols)), 'VariableNames', metaCols);
    end

    if ~isempty(removedSummary)
        removedTable = cell2table(vertcat(removedSummary{:}), 'VariableNames', removeCols);
    else
        removedTable = cell2table(cell(0, numel(removeCols)), 'VariableNames', removeCols);
    end

    writetable(keptTable, outputPath, 'Sheet', 'KeptTracks');
    writetable(removedTable, outputPath, 'Sheet', 'RemovedTracks');
end