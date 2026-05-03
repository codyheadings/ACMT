function mmsd = computeMSD(inputData, outputFolder, options)
% COMPUTEMSD Compute MSD from tracking data (table or file path)
%
% To learn more about MSD, visit https://tinevez.github.io/msdanalyzer/
%
% INPUT:
%
%   Required:
%       inputData: (table | string | char)
%           If table: Table with variables: T, X, Y, Z. If string/char array,
%           will be used as a file location to read as a table.
%
%   Optional:
%       outputFolder: (string, optional)
%           Folder to save figure.
%
%       options
%           
%           OutputFilename: (string | char, default = "MSD.fig")
%               Name and file extension to save the figure if outputFolder
%               is provided.
%
%           CreateFigure: (logical, default = true)
%               Generate the MSD graph. Set to false if you just want the
%               mmsd array.
%
%           Logs: (logical, default = true)
%               Print progress messages to console.
%
% OUTPUT:
%   mmsd: Mean MSD N x 4 double array. See @msdanalyzer for how to use
%   this array. Also optionally generates an MSD figure, saving it to the 
%   outputFolder if specified.

    arguments
        inputData {mustBeA(inputData,["table","string","char"])}
        outputFolder (1,1) string = ""
        options.OutputFilename (1,1) string = "MSD.fig"
        options.CreateFigure (1,1) logical = true
        options.Logs (1,1) logical = true
    end

    %% Load data (if needed)
    if istable(inputData)
        data = inputData;

    elseif isstring(inputData) || ischar(inputData)
        if ~isfile(inputData)
            error('computeMSD:fileNotFound', ...
                'File not found:\n%s', inputData);
        end
        data = readtable(inputData);

    else
        error('computeMSD:invalidInput', ...
            'Input must be a table or file path.');
    end

    requiredVars = {'T','X','Y','Z'};
    if ~all(ismember(requiredVars, data.Properties.VariableNames))
        error('computeMSD:missingVars', ...
            'Data must contain variables: T, X, Y, Z');
    end

    %% Segment tracks
    tracksTable = segmentTracks(data);

    if isempty(tracksTable)
        error('computeMSD:noTracks', 'No valid tracks found.');
    end

    %% Convert for msdanalyzer
    tracks = cell(numel(tracksTable),1);
    for i = 1:numel(tracksTable)
        t = tracksTable{i};
        tracks{i} = [t.T, t.X, t.Y, t.Z];
    end

    %% MSD analysis
    ma = msdanalyzer(3, 'µm', 'min');
    ma = ma.addAll(tracks);
    ma = ma.computeMSD;
    mmsd = ma.getMeanMSD;

    if options.CreateFigure
        if options.Logs
            fprintf('Plotting mean MSD figure...\n');
        end
    
        fig = figure('Name','MSD');
        ma.plotMeanMSD(gca, true);
    
        t = mmsd(:,1);
        msd = mmsd(:,2);
    
        hold on
        errorbar(t, msd, mmsd(:,3)./sqrt(mmsd(:,4)), 'k')
    
        if outputFolder ~= ""
            if ~isfolder(outputFolder), mkdir(outputFolder); end
            saveas(fig, fullfile(outputFolder, options.OutputFilename));
        end
    end
end