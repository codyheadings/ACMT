function aggregatedData = aggregateTrackingResults(rootFolder, outputFolder, options)
% AGGREGATETRACKINGRESULTS Run tracking results pipeline on a directory tree,
% and produce one results file per top-level folder.
%
% Every folder level above the tracker level is treated
% as an grouping category and becomes a "GroupN" column in the
% output. These can be edited manually after file creation. Cell distance 
% and speed calculations are run automatically on each collection and 
% results are grouped into one table per branch.
%
% INPUT:
%
% Required:
%   rootFolder: (char | string)
%       Path to top of the folder tree. Direct children of this folder
%       each produce one output .xlsx file.
%
%   outputFolder: (char | string)
%       Directory where output files are saved. Created automatically if
%       it does not exist.
%
% Optional: 
%   options
%
%       SaveAggregatedTracks: (logical, default: false)
%           Save a combined results file with all tracking data in one
%           list to the output folder. Useful for plotting representative 
%           tracks or running with other metric functions.
%
%       XYConversion: (double, default: 1)
%           Multiplicative factor applied to the X and Y columns.
%           Example: 0.65 converts 1 ImageJ pixel to 0.65 micrometers.
%
%       ZConversion: (double, default: 1)
%           Multiplicative factor applied to the Slice column to Z.
%           Example: 20 converts 1 slice index to 20 micrometers.
%
%       TConversion: (double, default: 1)
%           Multiplicative factor applied to Time column.
%           Example: 30 converts each frame number to 30 minutes.
%
%       OutputFilename: (char | string, default: "*_CombinedResults.xlsx")
%           Name of the output file. * is the name of the top-level folder.
%
%       ResultsFilename: (char | string, default: "Results.csv")
%           Name of the results file expected inside each tracker
%           subdirectory. By default ImageJ exports these as Results.csv.
%
%       Logs: (logical, default: true)
%           Print progress messages to the command window.
%
% OUTPUT:
%
%   aggregatedData: (cell array of tables)
%       One table per top-level subfolder, in the same order as the
%       subfolders appear on disk. Each table has the layout:
%           Group1, Group2, ... GroupN - folder-derived labels
%           TrackerName - tracker folder name
%           Cell - 1-based index per tracker
%           AvgCellSpeed - from cellSpeeds
%           CumulativeCellSpeed - from cellSpeeds
%           varianceEntirePeriod - from cellSpeeds
%           varianceFirstHalf - from cellSpeeds
%           varianceLastHalf - from cellSpeeds
%           AvgFrameDistance - from cellDistances
%           CumulativeDistance - from cellDistances
%           RelativeDisplacement - from cellDistances
%           DirectionalPersistence - from cellDistances
%
%   The same tables are also saved to outputFolder. 
%   If options.SaveAggregatedTracks is enabled (default: false) an
%   additional file will be saved with all cell tracks in one file.

    arguments
        rootFolder (1,1) string
        outputFolder (1,1) string
        options.SaveAggregatedTracks (1,1) logical = false
        options.XYConversion (1,1) double = 1
        options.ZConversion (1,1) double = 1
        options.TConversion (1,1) double = 1
        options.OutputFilename (1,1) string = "_CombinedResults.xlsx"
        options.ResultsFilename (1,1) string = "Results.csv"
        options.Logs (1,1) logical = true
    end

    if ~isfolder(rootFolder)
        error('aggregateTrackingResults:invalidRoot', ...
              'rootFolder does not exist:\n  %s', rootFolder);
    end

    if ~isfolder(outputFolder)
        mkdir(outputFolder);
    end

    topLevel = getSubdirs(rootFolder);

    if isempty(topLevel)
        error('aggregateTrackingResults:emptyRoot', ...
              'No subfolders found in rootFolder:\n  %s', rootFolder);
    end

    treeDepth = getTreeDepth(rootFolder, options.ResultsFilename);
 
    if treeDepth < 2
        error('aggregateTrackingResults:shallowTree', ...
              ['Tree must be at least 2 levels deep (one Group level ' ...
               'plus a tracker directory). Verify Results files exist ' ...
               'inside tracker subdirectories under rootFolder.']);
    end
 
    numGroups = treeDepth - 1;
    GroupColNames = arrayfun(@(n) sprintf('Group%d', n), ...
                                  1:numGroups, ...
                                  UniformOutput=false);

    aggregatedData = struct();
    aggregatedResults = table();

    for t = 1:numel(topLevel)
        topName = topLevel(t).name;
        topPath = fullfile(rootFolder, topName);
 
        if options.Logs
            fprintf('=== %s ===\n', topName);
        end
 
        trackerPaths = findTrackerPaths(topPath, options.ResultsFilename);
 
        if isempty(trackerPaths)
            warning('aggregateTrackingResults:noTrackerPaths', ...
                    'No valid tracker directories found under "%s". Skipping.', topName);
            continue
        end
 
        topTable = table();
 
        for L = 1:numel(trackerPaths)
            trackerDir = trackerPaths{L};
            [~, trackerName] = fileparts(trackerDir);
            
            GroupValues = extractGroupLabels( ...
                                  rootFolder, trackerDir, numGroups);

            parentDir = fileparts(trackerDir);
 
            try
                compiled = compileResultsFromCSV( ...
                    parentDir, ...
                    "", ...
                    XYConversion = options.XYConversion, ...
                    ZConversion = options.ZConversion, ...
                    TConversion = options.TConversion, ...
                    ResultsFilename = options.ResultsFilename, ...
                    Logs = false);
            catch ME
                warning('aggregateTrackingResults:compileFailed', ...
                        'compileResultsFromCSV failed for "%s":\n  %s', ...
                        parentDir, ME.message);
                continue
            end

            compiled = compiled(strcmp(compiled.TrackerName, trackerName), :);

            if height(compiled) > 0
                gpPrefix = buildGroupTable(GroupValues, GroupColNames, height(compiled));
                aggregatedResults = [aggregatedResults; [gpPrefix, compiled]]; %#ok<AGROW>
            end
 
            if isempty(compiled) || height(compiled) == 0
                if options.Logs
                    fprintf('  [skip]  No data compiled.\n');
                end
                continue
            end
 
            try
                distTable = cellDistances(compiled, "", Logs=false);
            catch ME
                warning('aggregateTrackingResults:distanceFailed', ...
                        'cellDistances failed for "%s":\n  %s', ...
                        parentDir, ME.message);
                continue
            end

            try
                speedTable = cellSpeeds(compiled, "", Logs=false);
            catch ME
                warning('aggregateTrackingResults:speedFailed', ...
                        'cellSpeeds failed for "%s":\n  %s', ...
                        parentDir, ME.message);
                continue
            end
 
            combined = outerjoin(speedTable, distTable, ...
                         'Keys', 'Cell', ...
                         'MergeKeys', true, ...
                         'Type', 'full');
            nRows = height(combined);
 
            gpTable = buildGroupTable(GroupValues, GroupColNames, nRows);
            trackerTable = table(repmat(string(trackerName), nRows, 1), ...
                                 'VariableNames', {'TrackerName'});
 
            rowTable = [gpTable, trackerTable, combined];
            topTable = [topTable; rowTable]; %#ok<AGROW>
 
            if options.Logs
                fprintf('  [ok]  %s / %s (%d cell(s))\n', ...
                        strjoin(GroupValues, '/'), trackerName, nRows);
            end
        end
 
        if height(topTable) == 0
            warning('aggregateTrackingResults:emptyTopLevel', ...
                    'No data collected for "%s". No file written.', topName);
            continue
        end
 
        % Write one Excel file for this top-level group
        outFilename = topName + options.OutputFilename;
        if options.OutputFilename ~= "_CombinedResults.xlsx"
            outFilename = options.OutputFilename;
        end
        outPath = fullfile(outputFolder, outFilename);
        writetable(topTable, outPath);
 
        if options.Logs
            fprintf('  Saved %d rows to %s\n\n', height(topTable), outPath);
        end
 
        aggregatedData.(matlab.lang.makeValidName(topName)) = topTable;
    end

    if options.SaveAggregatedTracks
        resultsOutPath = fullfile(outputFolder, "AggregatedTracks.xlsx");
        writetable(aggregatedResults, resultsOutPath);
        if options.Logs
            fprintf('Saved aggregated tracks to %s\n', resultsOutPath);
        end
    end
 
    if options.Logs
        fprintf('Done!\n');
    end

end


% LOCAL HELPER FUNCTIONS

function trackerPaths = findTrackerPaths(searchRoot, resultsFilename)
% FINDTRACKERPATHS Searches from SearchRoot until Results file is found.

    trackerPaths = {};
    subdirs = getSubdirs(searchRoot);
 
    for k = 1:numel(subdirs)
        subPath = fullfile(searchRoot, subdirs(k).name);
 
        if isfile(fullfile(subPath, resultsFilename))
            trackerPaths = [trackerPaths; {subPath}]; %#ok<AGROW>
        else
            deeper = findTrackerPaths(subPath, resultsFilename);
            trackerPaths = [trackerPaths; deeper]; %#ok<AGROW>
        end
    end
end

function subdirs = getSubdirs(folder)
% GETSUBDIRS Gets all children of an input folder

    entries = dir(folder);
    isSubDir = [entries.isdir];
    isDot = ismember({entries.name}, {'.', '..'});
    subdirs = entries(isSubDir & ~isDot);
end

function GroupValues = extractGroupLabels(rootFolder, trackerDir, numGroups)
    relPath = strrep(trackerDir, rootFolder, '');
 
    % Split on any path separators
    parts = strsplit(relPath, {filesep, '/', '\'});
    parts = parts(~cellfun(@isempty, parts));
 
    % parts = {Group1, Group2, ..., GroupN, TrackerName}
    gpParts = parts(1:end-1);
 
    if numel(gpParts) >= numGroups
        GroupValues = gpParts(1:numGroups);
    else
        pad = repmat({''}, 1, numGroups - numel(gpParts));
        GroupValues = [gpParts, pad];
    end
end
 
 
function gpTable = buildGroupTable(GroupValues, colNames, nRows)
    gpTable = table();
    for c = 1:numel(colNames)
        gpTable.(colNames{c}) = repmat(string(GroupValues{c}), nRows, 1);
    end
end

function depth = getTreeDepth(rootFolder, resultsFilename)
    depth = 0;
    current = rootFolder;
 
    while true
        subs = getSubdirs(current);
 
        if isempty(subs)
            if ~isfile(fullfile(current, resultsFilename))
                depth = 0;  % no Results file
            end
            return
        end

        depth = depth + 1;
        current = fullfile(current, subs(1).name);
    end
end
