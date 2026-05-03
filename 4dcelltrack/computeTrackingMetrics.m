function aggregatedResults = computeTrackingMetrics(aggregatedTracks, outputFolder, options)
% COMPUTETRACKINGMETRICS Run distance and speed analysis on a compiled
% tracking table and write one results file per top-level group.
%
% Takes the raw coordinate table produced by collectTrackingData (or
% filtered by filterDuplicateTracks) and computes per-cell distance and
% speed metrics for every tracker. Results are grouped by the top-level
% group value (Group1 column) and written to one .xlsx file per group.
%
% INPUTS:
% 
% Required:
%   aggregatedTracks: (table)
%       Raw coordinate table from collectTrackingData. Must contain:
%           Group1, ..., GroupN - group label columns (any names are fine
%                                  as long as they precede 'Num')
%           Num - row index within tracker file
%           TrackerName - tracker identifier
%           X, Y, Z - coordinates in physical units
%           T- time
%
%   outputFolder: (char | string)
%       Directory where output .xlsx files are saved. Created automatically
%       if it does not exist.
%
% Optional:
%   options
%
%       OutputFilename: (char | string, default: "_CombinedResults.xlsx")
%           Name appended to the Group1 value to form the output filename.
%
%       Logs: (logical, default: true)
%           Print progress messages to the command window.
%
% OUTPUT:
%
%   aggregatedResults: (struct)
%       One table field per unique Group1 value.
%       Layout:
%           Group1, Group2, ... GroupN - folder-derived group labels
%           TrackerName - tracker folder name
%           Cell - 1-based cell index per tracker
%           AvgCellSpeed - from cellSpeeds
%           CumulativeCellSpeed - from cellSpeeds
%           VarianceEntirePeriod - from cellSpeeds
%           VarianceFirstHalf - from cellSpeeds
%           VarianceLastHalf - from cellSpeeds
%           AvgFrameDistance - from cellDistances
%           CumulativeDistance - from cellDistances
%           RelativeDisplacement - from cellDistances
%           DirectionalPersistence - from cellDistances

    arguments
        aggregatedTracks (:,:) table
        outputFolder (1,1) string
        options.OutputFilename (1,1) string = "_CombinedResults.xlsx"
        options.Logs (1,1) logical = true
    end

    requiredCols = {'Num', 'TrackerName', 'X', 'Y', 'Z', 'T'};
    missingCols = requiredCols(~ismember(requiredCols, aggregatedTracks.Properties.VariableNames));
    if ~isempty(missingCols)
        error('computeTrackingMetrics:missingColumns', ...
              'aggregatedTracks is missing required column(s): %s\n', ...
              strjoin(missingCols, ', '));
    end

    if ~isfolder(outputFolder)
        mkdir(outputFolder);
    end

    % Detect group columns (everything before 'Num')
    allCols = aggregatedTracks.Properties.VariableNames;
    numColIdx = find(strcmp(allCols, 'Num'), 1);

    if numColIdx <= 1
        error('computeTrackingMetrics:noGroupCols', ...
              'No group columns found before "Num".');
    end

    groupColNames = allCols(1 : numColIdx - 1);
    topGroupCol = groupColNames{1};

    % Split by top-level group and process each
    topGroups = unique(aggregatedTracks.(topGroupCol), 'stable');
    aggregatedResults = struct();

    for g = 1:numel(topGroups)
        topName = topGroups{g};
        topBools = strcmp(aggregatedTracks.(topGroupCol), topName);
        topRows = aggregatedTracks(topBools, :);
        topTable = table();

        if options.Logs
            fprintf('=== %s ===\n', topName);
        end

        groupIDs = findgroups(topRows(:, [groupColNames, "TrackerName"]));

        for k = 1:max(groupIDs)
            compiled = topRows(groupIDs == k, :);
            trackerName = compiled.TrackerName{1};
        
            % Extract group values properly
            groupValues = cell(1, numel(groupColNames));
            for c = 1:numel(groupColNames)
                v = compiled.(groupColNames{c})(1);
                if iscell(v)
                    groupValues{c} = v{1};
                else
                    groupValues{c} = char(v);
                end
            end

            if height(compiled) == 0
                continue
            end

            % Read group label values for this tracker from their first row
            groupValues = cell(1, numel(groupColNames));
            for c = 1:numel(groupColNames)
                v = compiled.(groupColNames{c})(1);
                if iscell(v), groupValues{c} = v{1};
                else, groupValues{c} = char(v);
                end
            end

            % Run distance and speed analysis
            try
                distTable = cellDistances(compiled, "", Logs=false);
            catch ME
                warning('computeTrackingMetrics:distanceFailed', ...
                        'cellDistances failed for "%s":\n  %s', trackerName, ME.message);
                continue
            end

            try
                speedTable = cellSpeeds(compiled, "", Logs=false);
            catch ME
                warning('computeTrackingMetrics:speedFailed', ...
                        'cellSpeeds failed for "%s":\n  %s', trackerName, ME.message);
                continue
            end

            % Join distance and speed tables on Cell index
            combined = outerjoin(speedTable, distTable, ...
                         'Keys', 'Cell', ...
                         'MergeKeys', true, ...
                         'Type', 'full');
            nRows = height(combined);

            gpTable = buildGroupTable(groupValues, groupColNames, nRows);
            trackerTable = table(repmat(string(trackerName), nRows, 1), ...
                                 'VariableNames', {'TrackerName'});

            topTable = [topTable; [gpTable, trackerTable, combined]]; %#ok<AGROW>

            if options.Logs
                fprintf('  [ok]  %s / %s (%d cell(s))\n', ...
                        strjoin(groupValues, '/'), trackerName, nRows);
            end
        end

        if height(topTable) == 0
            warning('computeTrackingMetrics:emptyGroup', ...
                    'No data collected for "%s". No file written.', topName);
            continue
        end

        outFilename = string(topName) + options.OutputFilename;
        if options.OutputFilename ~= "_CombinedResults.xlsx"
            outFilename = options.OutputFilename;
        end
        outPath = fullfile(outputFolder, outFilename);
        writetable(topTable, outPath);

        if options.Logs
            fprintf('  Saved %d rows -> %s\n\n', height(topTable), outPath);
        end

        aggregatedResults.(matlab.lang.makeValidName(topName)) = topTable;
    end

    if options.Logs
        fprintf('Done!\n');
    end

end


% LOCAL HELPERS

function gpTable = buildGroupTable(groupValues, colNames, nRows)
% BUILDGROUPTABLE Create a table with one column per group level, each
% filled with nRows copies of the corresponding label string.
    gpTable = table();
    for c = 1:numel(colNames)
        gpTable.(colNames{c}) = repmat(string(groupValues{c}), nRows, 1);
    end
end