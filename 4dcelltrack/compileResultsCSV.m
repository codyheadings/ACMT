function compiledData = compileResultsCSV(inputFolder, outputFolder, options)
% COMPILERESULTSCSV Compile manual tracking results from multiple trackers
% into a single table with physical unit conversions applied.
%
% Scans an input folder for subdirectories (one per tracker). Within
% each tracker subdirectory it looks for a file named "Results.csv"
% (default) containing raw tracking coordinates. All valid results are
% concatenated into one table, optionally saved as a file.
%
% INPUT:
% 
% Required:
%   inputFolder: (char | string)
%       Path to the folder that contains one subdirectory per tracker, 
%       where each subdirectory contains a Results.csv file.
%
% Optional:
%   outputFolder: (char | string, default: "" (no file is written))
%       Directory where the compiled results file will be saved.
%       Created automatically if it does not exist.
%
%   options
%
%       XYScale: (double, default: 1)
%           Scale factor applied to the X and Y columns.
%
%       ZScale: (double, default: 1)
%           Scale factor applied to the Slice column to get Z.
%
%       TScale: (double, default: 1)
%           Scale factor applied to the Frame column to get Time (T).=
%
%       OutputFilename: (char | string, default: "CombinedResults.xlsx")
%           Name of the output file.
%
%       ResultsFilename: (char | string, default: "Results.csv")
%           Name of the results file expected inside each tracker
%           subdirectory. By default ImageJ exports these as Results.csv.
%
%       Logs: (logical, default: true)
%           Print progress messages to the command window.
%
% OUTPUT:
%   compiledData: (table)
%       Table with one row per tracking point across all trackers.
%       Columns:
%           Num - Row index within each tracker's original file
%           TrackerName - Name of the subdirectory (i.e., the tracker)
%           X - X coordinate in converted units
%           Y - Y coordinate in converted units
%           Z - Z coordinate in converted units
%           T - Time in converted units
%
%   If outputFolder is provided, the table is also saved with name 
%   specified in OutputFilename.

    arguments
        inputFolder (1,1) string
        outputFolder (1,1) string = ""
        options.XYScale (1,1) double = 1
        options.ZScale (1,1) double = 1
        options.TScale (1,1) double = 1
        options.OutputFilename (1,1) string = "CombinedResults.xlsx"
        options.ResultsFilename (1,1) string = "Results.csv"
        options.Logs (1,1) logical = true
    end

    if ~isfolder(inputFolder)
        error('compileResultsCSV:invalidInput', ...
              'inputFolder %s not found\n', inputFolder);
    end

    entries = dir(inputFolder);

    % Keep only subdirectories
    isSubDir = [entries.isdir];
    isDot = ismember({entries.name}, {'.', '..'});
    trackerDirs = entries(isSubDir & ~isDot);

    if isempty(trackerDirs)
        warning('compileResultsCSV:noSubdirs', ...
                'No subdirectories found in inputFolder %s \n', inputFolder);
        compiledData = table();
        return
    end

    compiledData = table();

    % Iterate over each tracker subdirectory
    for t = 1:numel(trackerDirs)
        trackerName = trackerDirs(t).name;
        resultsFile = fullfile(inputFolder, trackerName, options.ResultsFilename);

        % Skip if the results file is absent
        if ~isfile(resultsFile)
            if options.Logs
                fprintf('  [skip]  No %s found for tracker "%s"\n', ...
                        options.ResultsFilename, trackerName);
            end
            continue
        end

        % Load raw tracking data
        try
            rawData = readtable(resultsFile);
        catch ME
            warning('compileResultsCSV:readError', ...
                    'Could not read file:\n  %s\nReason: %s', ...
                    resultsFile, ME.message);
            continue
        end

        requiredCols = {'X', 'Y', 'Slice', 'Frame'};
        missingCols = requiredCols(~ismember(requiredCols, rawData.Properties.VariableNames));
        if ~isempty(missingCols)
            warning('compileResultsCSV:missingColumns', ...
                    'Skipping "%s": missing column(s): %s', ...
                    trackerName, strjoin(missingCols, ', '));
            continue
        end

        numRows = height(rawData);
        startRow = height(compiledData) + 1;

        % Suppress MATLAB's warnings temporarily
        warning('off', 'MATLAB:table:RowsAddedWithDefaultValues');
        warning('off', 'MATLAB:table:RowsAddedExistingVars');

        for i = 1:numRows
            currentRow = startRow + i - 1;
            row = rawData(i, :);

            compiledData.Num(currentRow) = i;

            compiledData.TrackerName(currentRow) = string(trackerName);

            compiledData.X(currentRow) = row.X * options.XYScale;
            compiledData.Y(currentRow) = row.Y * options.XYScale;
            compiledData.Z(currentRow) = row.Slice * options.ZScale;

            compiledData.T(currentRow) = (row.Frame - 1) * options.TScale;
        end

        % Re-enable warnings
        warning('on', 'MATLAB:table:RowsAddedWithDefaultValues');
        warning('on', 'MATLAB:table:RowsAddedExistingVars');

        if options.Logs
            fprintf('  [ok]  Loaded %d rows from tracker "%s"\n', numRows, trackerName);
        end
    end

    if height(compiledData) == 0
        warning('compileResultsCSV:noData', ...
                'No data collected. Check your Results.csv files.');
        return
    end

    if outputFolder ~= ""
        if ~isfolder(outputFolder)
            mkdir(outputFolder);
        end

        outputPath = fullfile(outputFolder, options.OutputFilename);

        writetable(compiledData, outputPath);

        if options.Logs
            fprintf('\nSaved %d total rows to:\n  %s\n', height(compiledData), outputPath);
        end
    end

    if options.Logs
        fprintf('Done! Compiled %d rows from %d tracker(s).\n', ...
                height(compiledData), numel(trackerDirs));
    end

end