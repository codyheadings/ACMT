function results = analyzeByGroup(inputData, swTestPath, groupColumn, outputFile, options)
% ANALYZEBYGROUP Full Statistical analysis using file created from 
% aggregateTrackingResults with normality testing.
% 
% Load compiled tracking results from aggregateTrackingResults,
% run Shapiro-Wilk normality tests per group, perform pairwise Mann-Whitney U
% between all group pairs, and write a multi-sheet Excel file.
%
% INPUT:
% 
% Required:
%   inputData: (table | string | char)
%       If string: Path to the .xlsx produced by aggregateTrackingResults.
%       If table: aggregatedData / filteredData table produced by the
%       respective functions.
%
%   swTestPath: (char | string)
%       Path to a folder containing swtest.m (Shapiro-Wilk test).
%
%   groupColumn: (char | string)
%       Name of the group column that defines the selection to be compared.
%       Example: 'Group2'
%
%   outputFile: (char | string)
%       Full path for the output .xlsx file (including filename).
%       The parent directory is created automatically if it does not exist.
%
% Optional:
%   Metrics: (cell array of char, default: all available metrics)
%       Selection of all metric columns to perform analysis on.
%       Defaults to all metrics present in the file that match the 
%       expected column names.
%
%   GroupColumns: (cell array of char, default: auto-detected)
%       Names of columns to use as descriptors in the wide-format metric
%       sheets (e.g. {'Group1','Group2','Group3','Group4'}).
%       Auto-detected if not supplied.
%
%   Logs: (logical, default: true)
%       Print progress messages to the command window.
%
% OUTPUT:
%
%   results: (struct)
%       .NormalityTests - table matching the Normality Tests sheet
%       .MetricTables - struct with one field per metric (wide-format table)
%       .PairwiseTests - struct with one field per group pair (comparison table)
%
% OUTPUT FILE SHEETS:
%
%   Normality Tests
%       Metric | Group | h_value | p_value
%       One row per metric-group combination. h=TRUE means non-normal.
%
%   <MetricName> (one sheet per metric)
%       Wide format: descriptor columns | Cell1 | Cell2 | ... | CellN | Average
%       Descriptor columns are all Group columns plus TrackerID.
%       Each row is one tracker/series combination; each CellN column is
%       that cell's value for the metric; trailing cells are blank. Useful
%       for making graphs from the raw data.
%
%   <GroupA> vs <GroupB> (one sheet per unique pair of groups)
%       Metric | p_value | h_value | <GroupA>_Mean | <GroupB>_Mean |
%       <GroupA>_Median | <GroupB>_Median

    arguments
        inputData {mustBeA(inputData,["table","string","char"])}
        swTestPath (1,1) string
        groupColumn (1,1) string
        outputFile (1,1) string
        options.Metrics cell = {}
        options.GroupColumns cell = {}
        options.Logs (1,1) logical = true
    end

   if istable(inputData)
        data = inputData;

    elseif isstring(inputData) || ischar(inputData)
        if ~isfile(inputData)
            error('analyzeByGroup:fileNotFound', ...
                'File not found:\n%s', inputData);
        end
        data = readtable(inputData, VariableNamingRule='preserve');

    else
        error('analyzeByGroup:invalidInput', ...
            'Input must be a table or file path.');
    end

    % Add swtest to path or throw error
    useSwTest = false;
    if isfolder(swTestPath)
        addpath(swTestPath);
        if exist('swtest', 'file') == 2
            useSwTest = true;
            if options.Logs
                fprintf('Using Shapiro-Wilk (swtest) for normality tests.\n');
            end
        end
    end
    if ~useSwTest
        error('analyzeByGroup:noSwTest', ...
            'swtest not found. Provide a valid path to swtest.m.');
    end

    if options.Logs
        fprintf('Loading inputData\n');
    end

    if ~ismember(groupColumn, data.Properties.VariableNames)
        error('analyzeByGroup:invalidGroupColumn', ...
              'Column "%s" not found. Available: %s', ...
              groupColumn, strjoin(data.Properties.VariableNames, ', '));
    end

    allCols = data.Properties.VariableNames;

    if isempty(options.GroupColumns)
        gpCols = allCols(startsWith(allCols, 'Group'));
    else
        gpCols = options.GroupColumns;
    end

    defaultMetrics = { ...
        'AvgCellSpeed', ...
        'CumulativeCellSpeed', ...
        'varianceEntirePeriod', ...
        'varianceFirstHalf', ...
        'varianceLastHalf', ...
        'AvgFrameDistance', ...
        'CumulativeDistance', ...
        'RelativeDisplacement', ...
        'DirectionalPersistence'};

    if isempty(options.Metrics)
        metrics = defaultMetrics(ismember(defaultMetrics, allCols));
    else
        metrics = options.Metrics;
        missing = metrics(~ismember(metrics, allCols));
        if ~isempty(missing)
            error('analyzeByGroup:missingMetrics', ...
                  'Requested metric(s) not found in file: %s', ...
                  strjoin(missing, ', '));
        end
    end

    if isempty(metrics)
        error('analyzeByGroup:noMetrics', ...
              'None of the expected metric columns were found in the input file.');
    end

    groupLabels = unique(data.(groupColumn), 'stable');
    numGroups = numel(groupLabels);

    if options.Logs
        fprintf('Groups (%s): %s\n', groupColumn, strjoin(string(groupLabels), ', '));
        fprintf('Metrics: %s\n', strjoin(metrics, ', '));
    end

    outputDir = fileparts(outputFile);
    if outputDir ~= "" && ~isfolder(outputDir)
        mkdir(outputDir);
    end

    %%  NORMALITY TESTS
    if options.Logs, fprintf('\nRunning normality tests...\n'); end

    normMetric = {};
    normGroup = {};
    normH = logical([]);
    normP = double([]);

    % Store per-group data for each metric
    groupData = struct();
    for g = 1:numGroups
        label = groupLabels{g};
        safeLabel = matlab.lang.makeValidName(label);
        bools = strcmp(data.(groupColumn), label);
        groupData.(safeLabel).rows = data(bools, :);
        groupData.(safeLabel).label = label;
    end

    for m = 1:numel(metrics)
        metric = metrics{m};

        for g = 1:numGroups
            label = groupLabels{g};
            safeLabel = matlab.lang.makeValidName(label);
            vals = extractNumericColumn(groupData.(safeLabel).rows, metric);
            vals = vals(~isnan(vals));

            [h, p] = runNormalityTest(vals, useSwTest);

            normMetric{end+1} = metric; %#ok<AGROW>
            normGroup{end+1} = label; %#ok<AGROW>
            normH(end+1) = logical(h); %#ok<AGROW>
            normP(end+1) = p; %#ok<AGROW>

            groupData.(safeLabel).normality.(matlab.lang.makeValidName(metric)) = h;
        end
    end

    normalityTable = table( ...
        normMetric', normGroup', normH', normP', ...
        'VariableNames', {'Metric', 'Group', 'h_value', 'p_value'});

    results.NormalityTests = normalityTable;

    %%  METRIC SHEETS
    %   Each row = one tracker identified by its group
    %   columns. Columns = Cell1, Cell2, ..., CellN, Average.
    if options.Logs, fprintf('Building metric sheets...\n'); end

    results.MetricTables = struct();

    descriptionCols = [gpCols, {'TrackerID'}];
    descriptionCols = descriptionCols(ismember(descriptionCols, allCols));

    % Find unique tracker rows
    if ~isempty(descriptionCols)
        descriptorData = data(:, descriptionCols);
        [~, firstIdx, ~] = unique(descriptorData, 'rows', 'stable');
        uniqueTrackerRows = data(firstIdx, descriptionCols);
    else
        uniqueTrackerRows = table();
        firstIdx = (1:height(data))';
    end

    for m = 1:numel(metrics)
        metric = metrics{m};
        fileRows = {};

        for r = 1:height(uniqueTrackerRows)
            bools = true(height(data), 1);
            for dc = 1:numel(descriptionCols)
                col = descriptionCols{dc};
                ref = uniqueTrackerRows.(col)(r);
                if iscell(data.(col))
                    bools = bools & strcmp(data.(col), ref);
                else
                    bools = bools & (data.(col) == ref);
                end
            end

            cellVals = extractNumericColumn(data(bools, :), metric);
            nCells = numel(cellVals);
            avgVal = mean(cellVals, 'omitnan');

            descVals = cell(1, numel(descriptionCols));
            for dc = 1:numel(descriptionCols)
                v = uniqueTrackerRows.(descriptionCols{dc})(r);
                if iscell(v)
                    descVals{dc} = v{1};
                else
                    descVals{dc} = v;
                end
            end

            fileRows{end+1} = [descVals, num2cell(cellVals'), {avgVal}]; %#ok<AGROW>
        end

        % Determine max number of cells across all trackers
        if isempty(fileRows)
            maxCells = 0;
        else
            maxCells = max(cellfun(@(r) numel(r) - numel(descriptionCols) - 1, fileRows));
        end

        % Pad rows to uniform width
        cellColNames = arrayfun(@(n) sprintf('Cell%d', n), 1:maxCells, ...
                                UniformOutput=false);
        colNames = [descriptionCols, cellColNames, {'Average'}];

        paddedRows = cellfun(@(row) padRow(row, numel(descriptionCols), maxCells), ...
                             fileRows, UniformOutput=false);

        if ~isempty(paddedRows)
            fileTable = cell2table(vertcat(paddedRows{:}), 'VariableNames', colNames);
        else
            fileTable = cell2table(cell(0, numel(colNames)), 'VariableNames', colNames);
        end

        safeMetric = matlab.lang.makeValidName(metric);
        results.MetricTables.(safeMetric) = fileTable;
    end

    %% PAIRWISE GROUP COMPARISON SHEETS
    if options.Logs, fprintf('Running pairwise group comparisons...\n'); end

    results.PairwiseTests = struct();
    groupPairs = {};

    for g1 = 1:numGroups
        for g2 = (g1+1):numGroups
            label1 = groupLabels{g1};
            label2 = groupLabels{g2};
            safe1 = matlab.lang.makeValidName(label1);
            safe2 = matlab.lang.makeValidName(label2);

            pairMetrics = {};
            pairP = double([]);
            pairH = logical([]);
            pairMean1 = double([]);
            pairMean2 = double([]);
            pairMedian1 = double([]);
            pairMedian2 = double([]);

            for m = 1:numel(metrics)
                metric = metrics{m};
                safeMetric = matlab.lang.makeValidName(metric);

                vals1 = extractNumericColumn(groupData.(safe1).rows, metric);
                vals2 = extractNumericColumn(groupData.(safe2).rows, metric);
                vals1 = vals1(~isnan(vals1));
                vals2 = vals2(~isnan(vals2));

                % Choose test based on per-group normality
                norm1 = ~groupData.(safe1).normality.(safeMetric); % h=0 means normal
                norm2 = ~groupData.(safe2).normality.(safeMetric);

                if norm1 && norm2
                    [hTest, pTest] = ttest2(vals1, vals2);
                else
                    [pTest, hTest] = ranksum(vals1, vals2);
                end

                pairMetrics{end+1} = metric; %#ok<AGROW>
                pairP(end+1) = pTest; %#ok<AGROW>
                pairH(end+1) = logical(hTest); %#ok<AGROW>
                pairMean1(end+1) = mean(vals1, 'omitnan'); %#ok<AGROW>
                pairMean2(end+1) = mean(vals2, 'omitnan'); %#ok<AGROW>
                pairMedian1(end+1) = median(vals1, 'omitnan'); %#ok<AGROW>
                pairMedian2(end+1) = median(vals2, 'omitnan'); %#ok<AGROW>
            end

            meanCol1 = sprintf('%s_Mean', label1);
            meanCol2 = sprintf('%s_Mean', label2);
            medianCol1 = sprintf('%s_Median', label1);
            medianCol2 = sprintf('%s_Median', label2);

            pairTable = table( ...
                pairMetrics', pairP', pairH', ...
                pairMean1', pairMean2', ...
                pairMedian1', pairMedian2', ...
                'VariableNames', {'Metric', 'p_value', 'h_value', ...
                                  meanCol1, meanCol2, ...
                                  medianCol1, medianCol2});

            pairKey = sprintf('%s_vs_%s', safe1, safe2);
            results.PairwiseTests.(pairKey) = pairTable;
            groupPairs{end+1} = struct( ...
                'label1', label1, 'label2', label2, ...
                'key', pairKey, 'table', pairTable); %#ok<AGROW>
        end
    end

    %% WRITE OUTPUT FILE
    if options.Logs, fprintf('Writing output file: %s\n', outputFile); end

    % Normality Tests
    writetable(normalityTable, outputFile, 'Sheet', 'Normality Tests');

    % One sheet per metric
    for m = 1:numel(metrics)
        safeMetric = matlab.lang.makeValidName(metrics{m});
        sheetName = metrics{m};
        writetable(results.MetricTables.(safeMetric), outputFile, 'Sheet', sheetName);
    end

    % One sheet per group pair
    for p = 1:numel(groupPairs)
        pair = groupPairs{p};
        sheetName = sprintf('%s vs %s', pair.label1, pair.label2);
        writetable(pair.table, outputFile, 'Sheet', sheetName);
    end

    if options.Logs
        fprintf('Done!\n');
    end

end


% LOCAL HELPER FUNCTIONS

function vals = extractNumericColumn(tbl, colName)
    raw = tbl.(colName);
    if iscell(raw)
        vals = cell2mat(raw);
    else
        vals = double(raw);
    end
    vals = vals(:);
end

function [h, p] = runNormalityTest(vals, useSwTest)
    if useSwTest
        [h, p] = swtest(vals);
    end
end

function row = padRow(row, numDescriptors, maxCells)
    nMetricCols = numel(row) - numDescriptors - 1;
    if nMetricCols < maxCells
        pad = repmat({[]}, 1, maxCells - nMetricCols);
        avg = row(end);
        row = [row(1:end-1), pad, avg];
    end
end
