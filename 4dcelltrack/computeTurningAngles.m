function angleTable = computeTurningAngles(inputData, outputFolder, options)
% COMPUTETURNINGANGLES Compute cell turning angles from tracking data.
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
%           Folder to save table.
%
%       options
%           
%           OutputFilename: (string | char, default = "TurningAngleResults.csv")
%               Name and file extension to save the figure if outputFolder
%               is provided.
%
%           Logs: (logical, default = true)
%               Print progress messages to console.
%
% OUTPUT:
%   angleTable: table with CellNum and TurningAngle_deg. If outputFolder is
%   specified, the table is saved there.

    arguments
        inputData {mustBeA(inputData,["table","string","char"])}
        outputFolder (1,1) string = ""
        options.OutputFilename (1,1) string = "TurningAngleResults.csv"
        options.Logs (1,1) logical = true
    end

    %% Load data
    if istable(inputData)
        data = inputData;

    elseif isstring(inputData) || ischar(inputData)
        if ~isfile(inputData)
            error('computeTurningAngles:fileNotFound', ...
                'File not found:\n%s', inputData);
        end
        data = readtable(inputData);

    else
        error('computeTurningAngles:invalidInput', ...
            'Input must be a table or file path.');
    end

    requiredVars = {'T','X','Y','Z'};
    if ~all(ismember(requiredVars, data.Properties.VariableNames))
        error('computeTurningAngles:missingVars', ...
            'Data must contain T, X, Y, Z');
    end

    %% Segment tracks
    tracks = segmentTracks(data);

    angleTable = table();

    for t = 1:numel(tracks)
        track = tracks{t};

        if height(track) < 3
            continue
        end

        dX = diff(track.X);
        dY = diff(track.Y);
        dZ = diff(track.Z);

        V = [dX dY dZ];

        angles = [];

        for i = 1:(size(V,1)-1)
            v1 = V(i,:);
            v2 = V(i+1,:);

            mag1 = norm(v1);
            mag2 = norm(v2);

            if mag1 == 0 || mag2 == 0
                continue
            end

            cosTheta = dot(v1,v2)/(mag1*mag2);
            cosTheta = max(-1,min(1,cosTheta));

            angles(end+1,1) = rad2deg(acos(cosTheta)); %#ok<AGROW>
        end

        if ~isempty(angles)
            temp = table( ...
                repmat(t,length(angles),1), ...
                angles, ...
                'VariableNames', {'CellNum','TurningAngle_deg'});

            angleTable = [angleTable; temp]; %#ok<AGROW>
        end
    end

    if outputFolder ~= ""
        if options.Logs
            fprintf('Saving table to %s...\n', outputFolder);
        end
        if ~isfolder(outputFolder), mkdir(outputFolder); end
        writetable(angleTable, fullfile(outputFolder, options.OutputFilename));
    end
end