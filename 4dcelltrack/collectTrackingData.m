function aggregatedTracks = collectTrackingData(rootFolder, options)
% COLLECTTRACKINGDATA Explore a folder tree and compile all raw tracking
% coordinates into a single tagged table, one row per timepoint.
%
% Traverses a directory tree ending in tracker folders containing
% Results.csv files. Every folder level above the tracker level becomes
% a "GroupN" column in the output, derived from the folder name at that
% level.
%
% INPUTS:
%
% Required:
%   rootFolder: (char | string)
%       Path to the root of the folder tree.
% 
% Optional:
%   options
%
%       XYScale: (double, default: 1)
%           Multiplicative factor applied to X and Y columns.
%
%       ZScale: (double, default: 1)
%           Multiplicative factor applied to the Slice column.
%
%       TScale: (double, default: 1)
%           Multiplicative factor applied to (Frame - 1).
%
%       ResultsFilename: (char | string, default: "Results.csv")
%           Name of the results file expected in each tracker directory.
%
%       OutputFile: (char | string, default: "" (no file written))
%           If provided, the compiled table is saved to this path.
%
%       Logs: (logical, default: true)
%           Print progress messages to the command window.
%
% OUTPUT:
%
%   aggregatedTracks: (table)
%       One row per timepoint across all trackers. Columns:
%           Group1, Group2, ... GroupN  - folder-derived group labels
%           Num - row index within tracker file
%           TrackerName - tracker folder name
%           X, Y, Z - coordinates in scaled units
%           T - time in scaled units, 0-based
%
% This table is the expected input for computeTrackingMetrics and
% filterDuplicateTracks.

    arguments
        rootFolder (1,1) string
        options.XYScale (1,1) double = 1
        options.ZScale (1,1) double = 1
        options.TScale (1,1) double = 1
        options.ResultsFilename (1,1) string = "Results.csv"
        options.OutputFile (1,1) string = ""
        options.Logs (1,1) logical = true
    end

    if ~isfolder(rootFolder)
        error('collectTrackingData:invalidRoot', ...
              'rootFolder does not exist:\n  %s', rootFolder);
    end

    % Measure tree depth and build group column names
    treeDepth = getTreeDepth(rootFolder, options.ResultsFilename);

    if treeDepth < 2
        error('collectTrackingData:shallowTree', ...
              ['Tree must be at least 2 levels deep (one group level ' ...
               'plus a tracker directory). Verify Results files exist ' ...
               'inside tracker subdirectories.']);
    end

    numGroups = treeDepth - 1;
    groupColNames = arrayfun(@(n) sprintf('Group%d', n), 1:numGroups, ...
                             UniformOutput=false);

    % Compile each tracker
    aggregatedTracks = table();
    trackerPaths = findTrackerPaths(rootFolder, options.ResultsFilename);

    if isempty(trackerPaths)
        warning('collectTrackingData:noTrackers', ...
                'No tracker directories found under rootFolder.');
        return
    end

    for L = 1:numel(trackerPaths)
        trackerDir = trackerPaths{L};
        [~, trackerName] = fileparts(trackerDir);
        parentDir = fileparts(trackerDir);

        groupValues = extractGroupLabels(rootFolder, trackerDir, numGroups);

        try
            compiled = compileResultsCSV( ...
                parentDir, "", ...
                XYScale = options.XYScale, ...
                ZScale = options.ZScale, ...
                TScale = options.TScale, ...
                ResultsFilename = options.ResultsFilename, ...
                Logs = false);
        catch ME
            warning('collectTrackingData:compileFailed', ...
                    'compileResultsCSV failed for "%s":\n  %s', ...
                    parentDir, ME.message);
            continue
        end

        % Keep only rows belonging to this specific tracker
        compiled = compiled(strcmp(compiled.TrackerName, trackerName), :);

        if height(compiled) == 0
            if options.Logs
                fprintf('  [skip]  No data for tracker "%s"\n', trackerName);
            end
            continue
        end

        % Prepend group columns
        gpPrefix = buildGroupTable(groupValues, groupColNames, height(compiled));
        aggregatedTracks = [aggregatedTracks; [gpPrefix, compiled]]; %#ok<AGROW>

        if options.Logs
            fprintf('  [ok]  %s / %s (%d row(s))\n', ...
                    strjoin(groupValues, '/'), trackerName, height(compiled));
        end
    end

    if height(aggregatedTracks) == 0
        warning('collectTrackingData:noData', 'No data collected.');
        return
    end

    if options.OutputFile ~= ""
        outDir = fileparts(options.OutputFile);
        if outDir ~= "" && ~isfolder(outDir)
            mkdir(outDir);
        end
        writetable(aggregatedTracks, options.OutputFile);
        if options.Logs
            fprintf('Saved %d rows -> %s\n', height(aggregatedTracks), options.OutputFile);
        end
    end

    if options.Logs
        fprintf('Done! Collected %d rows from %d tracker(s).\n', ...
                height(aggregatedTracks), numel(trackerPaths));
    end

end


% LOCAL HELPERS

function trackerPaths = findTrackerPaths(searchRoot, resultsFilename)
% FINDTRACKERPATHS Recursively collect all directories that directly
% contain resultsFilename.
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
% GETSUBDIRS Return immediate subdirectories, excluding . and ..
    entries = dir(folder);
    isSubDir = [entries.isdir];
    isDot = ismember({entries.name}, {'.', '..'});
    subdirs = entries(isSubDir & ~isDot);
end

function groupValues = extractGroupLabels(rootFolder, trackerDir, numGroups)
% EXTRACTGROUPLABELS Read folder names along the path from rootFolder to
% the parent of trackerDir to produce an ordered cell array of group labels.
    relPath = strrep(trackerDir, rootFolder, '');
    parts = strsplit(relPath, {filesep, '/', '\'});
    parts = parts(~cellfun(@isempty, parts));
    gpParts = parts(1:end-1);
    if numel(gpParts) >= numGroups
        groupValues = gpParts(1:numGroups);
    else
        pad = repmat({''}, 1, numGroups - numel(gpParts));
        groupValues = [gpParts, pad];
    end
end

function gpTable = buildGroupTable(groupValues, colNames, nRows)
% BUILDGROUPTABLE Create a table with one column per group level, each
% filled with nRows copies of the corresponding label string.
    gpTable = table();
    for c = 1:numel(colNames)
        gpTable.(colNames{c}) = repmat(string(groupValues{c}), nRows, 1);
    end
end

function depth = getTreeDepth(rootFolder, resultsFilename)
% GETTREEDEPTH Return the number of folder levels between rootFolder and
% the first tracker directory found.
    depth = 0;
    current = rootFolder;
    while true
        subs = getSubdirs(current);
        if isempty(subs)
            if ~isfile(fullfile(current, resultsFilename))
                depth = 0;
            end
            return
        end
        depth = depth + 1;
        current = fullfile(current, subs(1).name);
    end
end