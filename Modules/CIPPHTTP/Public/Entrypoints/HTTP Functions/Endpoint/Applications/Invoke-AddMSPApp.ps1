function Invoke-AddMSPApp {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.Application.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    $RMMApp = $Request.Body
    $RmmName = [string]$RMMApp.RMMName.value
    $SupportedRmmApps = @('datto', 'ninja', 'Huntress', 'syncro', 'NCentral', 'automate', 'cwcommand')

    if ([string]::IsNullOrWhiteSpace($RmmName) -or $SupportedRmmApps -notcontains $RmmName) {
        $Message = "Unknown MSP app type '{0}'. Supported values: {1}" -f $RmmName, ($SupportedRmmApps -join ', ')
        Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Warning'
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = [PSCustomObject]@{ Results = @($Message) }
            })
    }

    $AssignTo = $Request.Body.AssignTo -eq 'customGroup' ? $Request.Body.CustomGroup : $Request.Body.AssignTo
    $intuneBody = Get-Content "AddMSPApp\$RmmName.app.json" | ConvertFrom-Json
    $intuneBody.displayName = $RMMApp.DisplayName

    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
    $Tenants = $Request.Body.selectedTenants | Where-Object { $AllowedTenants -contains $_.customerId -or $AllowedTenants -contains 'AllTenants' }
    $SuccessCount = 0
    $ErrorCount = 0
    $Results = foreach ($Tenant in $Tenants) {
        # Build the install/uninstall command lines for this tenant. Get-CIPPMSPAppInstallCommand
        # resolves each param whether it is a per-tenant keyed value (interactive deploy) or a
        # flat value / %CIPP variable% (Application Template deploy).
        $CommandResult = Get-CIPPMSPAppInstallCommand -RmmName $RmmName -Params $RMMApp.params -Tenant $Tenant -PackageName $RMMApp.PackageName
        $intuneBody.installCommandLine = $CommandResult.InstallCommandLine
        $intuneBody.UninstallCommandLine = $CommandResult.UninstallCommandLine
        if ($CommandResult.DetectionScriptContent) {
            $intuneBody.detectionRules[0].scriptContent = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($CommandResult.DetectionScriptContent))
        }


        try {
            $CompleteObject = [PSCustomObject]@{
                tenant          = $Tenant.defaultDomainName
                ApplicationName = $RMMApp.DisplayName
                assignTo        = $AssignTo
                IntuneBody      = $intuneBody
                type            = 'MSPApp'
                MSPAppName      = $RMMApp.RMMName.value
            } | ConvertTo-Json -Depth 15
            $Table = Get-CippTable -tablename 'apps'
            $Table.Force = $true
            Add-CIPPAzDataTableEntity @Table -Entity @{
                JSON         = "$CompleteObject"
                RowKey       = "$((New-Guid).GUID)"
                PartitionKey = 'apps'
                status       = 'Not Deployed yet'
            }
            $SuccessCount++
            "Successfully added MSP App for $($Tenant.defaultDomainName) to queue. "
            Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant.defaultDomainName -message "MSP Application $($intuneBody.DisplayName) added to queue" -Sev 'Info'
        } catch {
            $ErrorCount++
            Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant.defaultDomainName -message "Failed to add MSP Application $($intuneBody.DisplayName) to queue" -Sev 'Error'
            "Failed to add MSP app for $($Tenant.defaultDomainName) to queue"
        }
    }

    $StatusCode = [HttpStatusCode]::OK
    if ($ErrorCount -gt 0 -and $SuccessCount -eq 0) {
        $StatusCode = [HttpStatusCode]::InternalServerError
    } elseif ($ErrorCount -gt 0) {
        $StatusCode = [HttpStatusCode]::MultiStatus
    }

    $body = [PSCustomObject]@{'Results' = $Results }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })

}
