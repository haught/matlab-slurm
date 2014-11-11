function jobID = extractJobId(cmdOut)
% Extracts the job ID from the sbatch command output for SLURM

% Copyright 2010-2011 The MathWorks, Inc.

% The output of sbatch will be:
% Submitted batch job 41600.
jobNumberStr = regexp(cmdOut, 'job [0-9]*', 'once', 'match');
jobID = sscanf(jobNumberStr, 'job %d');
dctSchedulerMessage(0, '%s: Job ID %d was extracted from sbatch output %s.', mfilename, jobID, cmdOut);
