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
        $InstallParams = [PSCustomObject]$RMMApp.params
        switch ($RmmName) {
            'datto' {
                Write-Host 'Processing Datto installation'
                $DattoUrl = ConvertTo-CIPPSafePwshArg -Value ([string]$InstallParams.DattoURL)
                $DattoGuid = ConvertTo-CIPPSafePwshArg -Value ([string]$InstallParams.DattoGUID."$($Tenant.customerId)")
                $installCommandLine = "powershell.exe -ExecutionPolicy Bypass .\install.ps1 -URL $DattoUrl -GUID $DattoGuid"
                $uninstallCommandLine = 'powershell.exe -ExecutionPolicy Bypass .\uninstall.ps1'
            }
            'ninja' {
                Write-Host 'Processing Ninja installation'
                $NinjaPackage = ConvertTo-CIPPSafePwshArg -Value ([string]$RMMApp.PackageName)
                $installCommandLine = "powershell.exe -ExecutionPolicy Bypass .\install.ps1 -InstallParam $NinjaPackage"
                $uninstallCommandLine = 'powershell.exe -ExecutionPolicy Bypass .\uninstall.ps1'
            }
            'Huntress' {
                $HuntressOrgKey = ConvertTo-CIPPSafePwshArg -Value ([string]$InstallParams.Orgkey."$($Tenant.customerId)")
                $HuntressAccountKey = ConvertTo-CIPPSafePwshArg -Value ([string]$InstallParams.AccountKey)
                $installCommandLine = "powershell.exe -ExecutionPolicy Bypass .\install.ps1 -OrgKey $HuntressOrgKey -acctkey $HuntressAccountKey"
                $uninstallCommandLine = 'powershell.exe -ExecutionPolicy Bypass .\install.ps1 -Uninstall'
            }
            'syncro' {
                $SyncroUrl = ConvertTo-CIPPSafePwshArg -Value ([string]$InstallParams.ClientURL."$($Tenant.customerId)")
                $installCommandLine = "powershell.exe -ExecutionPolicy Bypass .\install.ps1 -URL $SyncroUrl"
                $uninstallCommandLine = 'powershell.exe -ExecutionPolicy Bypass .\uninstall.ps1'
            }
            'NCentral' {
                $NCentralPackage = ConvertTo-CIPPSafePwshArg -Value ([string]$RMMApp.PackageName)
                $installCommandLine = "powershell.exe -ExecutionPolicy Bypass .\install.ps1 -InstallParam $NCentralPackage"
                $uninstallCommandLine = 'powershell.exe -ExecutionPolicy Bypass .\uninstall.ps1'
            }
            'automate' {
                $AutomateServer = ConvertTo-CIPPSafePwshArg -Value ([string]$InstallParams.Server)
                $AutomateInstallerToken = ConvertTo-CIPPSafePwshArg -Value ([string]$InstallParams.InstallerToken."$($Tenant.customerId)")
                $AutomateLocationId = ConvertTo-CIPPSafePwshArg -Value ([string]$InstallParams.LocationID."$($Tenant.customerId)")
                $installCommandLine = "c:\windows\sysnative\windowspowershell\v1.0\powershell.exe -ExecutionPolicy Bypass .\install.ps1 -Server $AutomateServer -InstallerToken $AutomateInstallerToken -LocationID $AutomateLocationId"
                $uninstallCommandLine = "c:\windows\sysnative\windowspowershell\v1.0\powershell.exe -ExecutionPolicy Bypass .\uninstall.ps1 -Server $AutomateServer"
                $DetectionScript = (Get-Content 'AddMSPApp\automate.detection.ps1' -Raw) -replace '##SERVER##', $InstallParams.Server
                $intuneBody.detectionRules[0].scriptContent = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($DetectionScript))
            }
            'cwcommand' {
                $CwClientUrl = ConvertTo-CIPPSafePwshArg -Value ([string]$InstallParams.ClientURL."$($Tenant.customerId)")
                $installCommandLine = "powershell.exe -ExecutionPolicy Bypass .\install.ps1 -Url $CwClientUrl"
                $uninstallCommandLine = 'powershell.exe -ExecutionPolicy Bypass .\uninstall.ps1'
            }
            default {
                throw "Unknown MSP app type '$RmmName'"
            }
        }
        $intuneBody.installCommandLine = $installCommandLine
        $intuneBody.UninstallCommandLine = $uninstallCommandLine


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
