using namespace System.Net

Function Invoke-AddMSPApp {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Application.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $RMMApp = $Request.Body
    $AssignTo = $Request.Body.AssignTo
    $intuneBody = Get-Content "AddMSPApp\$($RMMApp.RMMName.value).app.json" | ConvertFrom-Json
    $intuneBody.displayName = $RMMApp.DisplayName

    $Tenants = $Request.Body.selectedTenants
    $Results = foreach ($Tenant in $Tenants) {
        $InstallParams = [PSCustomObject]$RMMApp.params
        switch ($RMMApp.RMMName.value) {
            'datto' {
                Write-Host 'Processing Datto installation'
                $installCommandLine = "powershell.exe -ExecutionPolicy Bypass .\install.ps1 -URL $($InstallParams.DattoURL) -GUID $($InstallParams.DattoGUID."$($Tenant.customerId)")"
                $uninstallCommandLine = 'powershell.exe -ExecutionPolicy Bypass .\uninstall.ps1'
            }
            'ninja' {
                Write-Host 'Processing Ninja installation'
                $installCommandLine = "powershell.exe -ExecutionPolicy Bypass .\install.ps1 -InstallParam $($RMMApp.PackageName)"
                $uninstallCommandLine = 'powershell.exe -ExecutionPolicy Bypass .\uninstall.ps1'
            }
            'Huntress' {
                $installCommandLine = "powershell.exe -ExecutionPolicy Bypass .\install.ps1 -OrgKey $($InstallParams.Orgkey."$($Tenant.customerId)") -acctkey $($InstallParams.AccountKey)"
                $uninstallCommandLine = 'powershell.exe -ExecutionPolicy Bypass .\install.ps1 -Uninstall'
            }
            'Immybot' {
                $installCommandLine = "powershell.exe -ExecutionPolicy Bypass .\install.ps1 -url $($InstallParams.ClientURL."$($tenant.customerId)")"
                $UninstallCommandLine = 'powershell.exe -ExecutionPolicy Bypass .\uninstall.ps1'
            }
            'syncro' {
                $installCommandLine = "powershell.exe -ExecutionPolicy Bypass .\install.ps1 -URL $($InstallParams.ClientURL."$($Tenant.customerId)")"
                $uninstallCommandLine = 'powershell.exe -ExecutionPolicy Bypass .\uninstall.ps1'
            }
            'NCentral' {
                $installCommandLine = "powershell.exe -ExecutionPolicy Bypass .\install.ps1 -InstallParam $($RMMApp.PackageName)"
                $uninstallCommandLine = 'powershell.exe -ExecutionPolicy Bypass .\uninstall.ps1'
            }
            'automate' {
                $installCommandLine = "c:\windows\sysnative\windowspowershell\v1.0\powershell.exe -ExecutionPolicy Bypass .\install.ps1 -Server $($InstallParams.Server) -InstallerToken $($InstallParams.InstallerToken."$($Tenant.customerId)") -LocationID $($InstallParams.LocationID."$($Tenant.customerId)")"
                $uninstallCommandLine = "c:\windows\sysnative\windowspowershell\v1.0\powershell.exe -ExecutionPolicy Bypass .\uninstall.ps1 -Server $($InstallParams.Server)"
                $DetectionScript = (Get-Content 'AddMSPApp\automate.detection.ps1' -Raw) -replace '##SERVER##', $InstallParams.Server
                $intuneBody.detectionRules[0].scriptContent = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($DetectionScript))
            }
            'cwcommand' {
                $installCommandLine = "powershell.exe -ExecutionPolicy Bypass .\install.ps1 -Url $($InstallParams.ClientURL."$($Tenant.customerId)")"
                $uninstallCommandLine = 'powershell.exe -ExecutionPolicy Bypass .\uninstall.ps1'
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
            "Successfully added MSP App for $($Tenant.defaultDomainName) to queue. "
            Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant.defaultDomainName -message "MSP Application $($intuneBody.DisplayName) added to queue" -Sev 'Info'
        } catch {
            Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant.defaultDomainName -message "Failed to add MSP Application $($intuneBody.DisplayName) to queue" -Sev 'Error'
            "Failed to add MSP app for $($Tenant.defaultDomainName) to queue"
        }
    }


    $body = [PSCustomObject]@{'Results' = $Results }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
