    using namespace System.Net

    Function Invoke-AddChocoApp_OrchestrationStarterTimer {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

                Write-LogMessage -API 'ChocoApps' -message 'Attempted to start upload but an instance was already running.' -sev Info
    }
    else {
        $InstanceId = Start-NewOrchestration -FunctionName 'Applications_Orchestrator'
        Write-Host "Started orchestration with ID = '$InstanceId'"
        $Orchestrator = New-OrchestrationCheckStatusResponse -Request $Timer -InstanceId $InstanceId
        Write-LogMessage -API 'ChocoApps' -message 'Started uploading applications to tenants' -sev Info
        $Results = [pscustomobject]@{'Results' = 'Started running analysis' }
    }
    Write-Host ($Orchestrator | ConvertTo-Json)
}
catch {
    Write-Host "AddChocoApp_OrchestratorStarterTimer Exception: $($_.Exception.Message)"
}

    }
