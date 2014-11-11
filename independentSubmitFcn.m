function independentSubmitFcn(cluster, job, props)
%INDEPENDENTSUBMITFCN Submit a MATLAB job to a LSF cluster
%
% Set your cluster's IndependentSubmitFcn to this function using the following
% command:
%     set(cluster, 'IndependentSubmitFcn', @independentSubmitFcn);
%
% See also parallel.cluster.generic.independentDecodeFcn.
%

% Copyright 2010-2013 The MathWorks, Inc.

% Store the current filename for the errors, warnings and dctSchedulerMessages
currFilename = mfilename;
if ~isa(cluster, 'parallel.Cluster')
    error('parallelexamples:GenericLSF:SubmitFcnError', ...
        'The function %s is for use with clusters created using the parcluster command.', currFilename)
end

decodeFunction = 'parallel.cluster.generic.independentDecodeFcn';

if ~cluster.HasSharedFilesystem
    error('parallelexamples:GenericLSF:SubmitFcnError', ...
        'The submit function %s is for use with shared filesystems.', currFilename)
end

if ~strcmpi(cluster.OperatingSystem, 'unix')
    error('parallelexamples:GenericLSF:SubmitFcnError', ...
        'The submit function %s only supports clusters with unix OS.', currFilename)
end

% The job specific environment variables
% Remove leading and trailing whitespace from the MATLAB arguments
matlabArguments = strtrim(props.MatlabArguments);
variables = {'MDCE_DECODE_FUNCTION', decodeFunction; ...
    'MDCE_STORAGE_CONSTRUCTOR', props.StorageConstructor; ...
    'MDCE_JOB_LOCATION', props.JobLocation; ...
    'MDCE_MATLAB_EXE', props.MatlabExecutable; ... 
    'MDCE_MATLAB_ARGS', matlabArguments; ...
    'MDCE_DEBUG', 'true'; ...
    'MLM_WEB_LICENSE', props.UseMathworksHostedLicensing; ...
    'MLM_WEB_USER_CRED', props.UserToken; ...
    'MLM_WEB_ID', props.LicenseWebID; ...
    'MDCE_LICENSE_NUMBER', props.LicenseNumber; ...
    'MDCE_STORAGE_LOCATION', props.StorageLocation};
% Trim the environment variables of empty values.
nonEmptyValues = cellfun(@(x) ~isempty(strtrim(x)), variables(:,2));
variables = variables(nonEmptyValues, :);
% Set the remaining non-empty environment variables
for ii = 1:size(variables, 1)
    setenv(variables{ii,1}, variables{ii,2});
end


% Deduce the correct quote to use based on the OS of the current machine
if ispc
    quote = '"';
else 
    quote = '''';
end



% The script name is independentJobWrapper.sh
scriptName = 'independentJobWrapper.sh';
% The wrapper script is in the same directory as this file
dirpart = fileparts(mfilename('fullpath'));
quotedScriptName = sprintf('%s%s%s', quote, fullfile(dirpart, scriptName), quote);

% Get the tasks for use in the loop
tasks = job.Tasks;
numberOfTasks = props.NumberOfTasks;
jobIDs = cell(numberOfTasks, 1);

% Loop over every task we have been asked to submit
for ii = 1:numberOfTasks
    taskLocation = props.TaskLocations{ii};
    % Set the environment variable that defines the location of this task
    setenv('MDCE_TASK_LOCATION', taskLocation);
    
    % Choose a file for the output. Please note that currently, JobStorageLocation refers
    % to a directory on disk, but this may change in the future.
    logFile = cluster.getLogLocation(tasks(ii));
    quotedLogFile = sprintf('%s%s%s', quote, logFile, quote);
    
    % Submit one task at a time
    jobName = sprintf('Job%d.%d', job.ID, tasks(ii).ID);
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% CUSTOMIZATION MAY BE REQUIRED %%
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % You may also with to supply additional submission arguments to 
    % the bsub command here.
    additionalSubmitArgs = '';
    dctSchedulerMessage(5, '%s: Generating command for task %i', currFilename, ii);
    commandToRun = getSubmitString(jobName, quotedLogFile, quotedScriptName, ...
        additionalSubmitArgs);   
    
    
    % Now ask the cluster to run the submission command
    dctSchedulerMessage(4, '%s: Submitting job using command:\n\t%s', currFilename, commandToRun);
    try
        % Make the shelled out call to run the command.
        [cmdFailed, cmdOut] = system(commandToRun);
    catch err
        cmdFailed = true;
        cmdOut = err.message;
    end
    if cmdFailed
        error('parallelexamples:GenericLSF:SubmissionFailed', ...
            'Submit failed with the following message:\n%s', cmdOut);
    end
    
    dctSchedulerMessage(1, '%s: Job output will be written to: %s\nSubmission output: %s\n', currFilename, logFile, cmdOut);
    jobIDs{ii} = extractJobId(cmdOut);
    
    if isempty(jobIDs{ii})
        warning('parallelexamples:GenericLSF:FailedToParseSubmissionOutput', ...
            'Failed to parse the job identifier from the submission output: "%s"', ...
            cmdOut);
    end
end

% set the job ID on the job cluster data
cluster.setJobClusterData(job, struct('ClusterJobIDs', {jobIDs}));

