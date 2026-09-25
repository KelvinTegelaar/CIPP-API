function Invoke-AddBaseline {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Baselines.ReadWrite
    .DESCRIPTION
        Creates or updates a baseline. There is no baseline blob: the Baselines
        delta rows (design doc §4.1) are the editable source of truth for every standard's
        configuration, and the BaselineRollouts row (§12.2) holds the baseline-level data -
        name, description, exclusions, alert destinations, and the ordered stage definitions.
        Baselines are reconstructed from those rows on read. The actual write lives in
        New-CIPPBaseline, shared with the community-repo import.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    try {
        # Optional. Pushes the saved baseline to a GitHub template repository after the save: FullName is
        # the repository (owner/repo), Message is the commit message. Not stored on the baseline.
        $GitHubPush = $Request.Body.GitHub
        if ($Request.Body.PSObject.Properties.Name -contains 'GitHub') {
            $Request.Body.PSObject.Properties.Remove('GitHub')
        }

        $User = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails

        # A synced baseline saved with no GitHub block is a local edit not yet in the repo -
        # flag it now. When a GitHub block is sent, leave the flag alone here; it is cleared
        # after the push succeeds below, so a failed push leaves it true.
        $ExistingHasSource = $false
        if ($Request.Body.GUID) {
            $RolloutTable = Get-CIPPTable -TableName BaselineRollouts
            $SafeGuid = ConvertTo-CIPPODataFilterValue -Value $Request.Body.GUID
            $ExistingRollout = Get-CIPPAzDataTableEntity @RolloutTable -Filter "PartitionKey eq 'rollout' and RowKey eq '$SafeGuid'" | Select-Object -First 1
            $ExistingHasSource = Test-CIPPRepoSource -Source $ExistingRollout.Source
        }

        if (-not $GitHubPush.FullName -and $ExistingHasSource) {
            $Saved = New-CIPPBaseline -Baseline $Request.Body -User $User -LocalChanges:$true
        } else {
            $Saved = New-CIPPBaseline -Baseline $Request.Body -User $User
        }

        Write-LogMessage -headers $Request.Headers -API $APIName -message "Baseline $($Request.Body.templateName) ($($Saved.GUID)) saved; $($Saved.DeltaCount) delta rows written." -Sev 'Info'

        $ResultsMessage = 'Successfully saved the baseline'
        if ($GitHubPush.FullName) {
            try {
                $PushResult = Push-CIPPBaselineToRepo -GUID $Saved.GUID -FullName $GitHubPush.FullName -Message $GitHubPush.Message
                if ($PushResult.state -eq 'success') {
                    $ResultsMessage = "$ResultsMessage. Pushed to $($GitHubPush.FullName)."
                } else {
                    Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to push baseline $($Saved.GUID) to $($GitHubPush.FullName): $($PushResult.resultText)" -Sev 'Error'
                    $ResultsMessage = "$ResultsMessage. Failed to push to $($GitHubPush.FullName): $($PushResult.resultText)"
                }
            } catch {
                Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to push baseline $($Saved.GUID) to $($GitHubPush.FullName): $($_.Exception.Message)" -Sev 'Error'
                $ResultsMessage = "$ResultsMessage. Failed to push to $($GitHubPush.FullName): $($_.Exception.Message)"
            }
        }
        $Results = [pscustomobject]@{ Results = $ResultsMessage; Metadata = @{ id = $Saved.GUID; deltas = $Saved.DeltaCount } }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to save baseline: $($_.Exception.Message)" -Sev 'Error'
        $Results = [pscustomobject]@{ Results = "Failed to save baseline: $($_.Exception.Message)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
