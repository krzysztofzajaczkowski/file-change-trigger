<#
    .SYNOPSIS
    This script triggers repository workflow if specified directory/file were updated.
    .DESCRIPTION
    GitHub repository workflow is triggered on directory/file updates.
    .PARAMETER owner
    Owner of repository to check for changes
    .PARAMETER triggerOwner
    Owner of triggered repository
    .PARAMETER repository
    Name of repository to check for changes
    .PARAMETER triggerRepository
    Name of triggered repository
    .PARAMETER workflowFileName
    Name of workflow file to trigger
    .PARAMETER workflowName
    Name of workflow to check
    .PARAMETER checkForChangesIn
    Path to directory/file to check for updates
    .PARAMETER username
    Username for GitHub API calls authentication
    .PARAMETER authToken
    Token for GitHub API calls authentication
    .NOTES
    Written by Krzysztof Zajączkowski
    @krzysztofzajaczkowski
    #>
    param(
        [parameter(Mandatory = $true)]
        [string]$Owner,

        [parameter(Mandatory = $true)]
        [string]$TriggerOwner,

        [parameter(Mandatory = $true)]
        [string]$Repository,

        [parameter(Mandatory = $true)]
        [string]$TriggerRepository,

        [parameter(Mandatory = $true)]
        [string]$WorkflowFileName,

        [parameter(Mandatory = $true)]
        [string]$WorkflowName,

        [parameter(Mandatory = $true)]
        [string]$CheckForChangesIn,

        [parameter(Mandatory = $true)]
        [string]$Username,

        [parameter(Mandatory = $true)]
        [string]$AuthToken
    )

    function Get-BasicAuthCreds {
        param([string]$Username,[string]$AuthToken)
        $AuthString = "{0}:{1}" -f $Username,$AuthToken
        $AuthBytes  = [System.Text.Encoding]::Ascii.GetBytes($AuthString)
        return [Convert]::ToBase64String($AuthBytes)
    }

    $token = Get-BasicAuthCreds -Username $Username -AuthToken $AuthToken


    # get date of last change to path
    $commitsUri = "https://api.github.com/repos/$($Owner)/$($Repository)/commits?path=$($CheckForChangesIn)&page=1&per_page=1"
    $commitsResponse = Invoke-WebRequest -Uri $commitsUri -Headers @{"Authorization"="Basic $token"} -SkipHttpErrorCheck
    # get date of last workflow
    $workflowRunsUri = "https://api.github.com/repos/$($TriggerOwner)/$($TriggerRepository)/actions/runs"
    $workflowRunsResponse = Invoke-WebRequest -Uri $workflowRunsUri -Headers @{"Authorization"="Basic $token"} -SkipHttpErrorCheck

    # check if both requests were successful
    if (($commitsResponse.StatusCode -eq 200) -and ($workflowRunsResponse.StatusCode -eq 200)) {
        # select commit date from first element of response array by accessing member .commit.commiter.date
        $commitDate = ($commitsResponse | ConvertFrom-Json | Select-Object -First 1).commit.committer.date
        # select last successful workflow run date by selecting first element from workflow_runs
        # where workflow name matches, status is completed" and conclusion is "success" and accessing member .run_started_at
        $lastSuccessfulRunDate = (($workflowRunsResponse | ConvertFrom-Json).workflow_runs | Where-Object `
         {($_.name -eq $WorkflowName) -and ($_.status -eq "completed") -and ($_.conclusion -eq "success")} | Select-Object -First 1).run_started_at

        # if date of last change is later than date of last workflow
        if ($commitDate -gt $lastSuccessfulRunDate) {
            # trigger workflow
            $triggerWorkflowUri = "https://api.github.com/repos/$($TriggerOwner)/$($TriggerRepository)/actions/workflows/$($WorkflowFileName)/dispatches"
            $body = @{
                "ref"="master"
            }
            $triggerWorkflowResponse = Invoke-WebRequest -Uri $triggerWorkflowUri -Headers @{"Authorization"="Basic $token"} -SkipHttpErrorCheck -Method POST `
                -Body ($body|ConvertTo-Json) -ContentType "application/json"

            if ($triggerWorkflowResponse.StatusCode -ne 204) {
                throw "Triggering $($TriggerRepository) workflow has failed with message $($triggerWorkflowResponse.Content)!"
            }

        }

    }