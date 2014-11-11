function submitString = getSubmitString(jobName, quotedLogFile, quotedCommand, ...
    additionalSubmitArgs)
%GETSUBMITSTRING Gets the correct sbatch command for an SLURM cluster

% Copyright 2010-2011 The MathWorks, Inc.

% Submit to SLURM using sbatch.  Note the following:
% "-J " - specifies the job name
% "-o" - specifies where standard output goes to (and standard error, when -e is not specified)
% Note that extra spaces in the sbatch command are permitted
submitString = sprintf('sbatch -J %s -o %s %s %s', jobName, quotedLogFile, additionalSubmitArgs, quotedCommand);
