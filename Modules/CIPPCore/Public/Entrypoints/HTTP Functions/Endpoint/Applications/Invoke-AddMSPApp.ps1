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

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    Write-Host 'PowerShell HTTP trigger function processed a request.'
    $RMMApp = $request.body
    $assignTo = $Request.body.AssignTo
    $intuneBody = Get-Content "AddMSPApp\$($RMMApp.RMMName.value).app.json" | ConvertFrom-Json
    $intuneBody.displayName = $RMMApp.DisplayName

    $Tenants = $request.body.selectedTenants
    $Results = foreach ($Tenant in $tenants) {
        $InstallParams = [pscustomobject]$RMMApp.params
        switch ($rmmapp.RMMName.value) {
            'datto' {
                $installcommandline = "powershell.exe -executionpolicy bypass .\install.ps1 -URL $($InstallParams.DattoURL) -GUID $($InstallParams.DattoGUID["$($tenant.customerId)"])"
                $UninstallCommandLine = 'powershell.exe -executionpolicy bypass .\uninstall.ps1'
            }
            'ninja' {
                $installcommandline = "powershell.exe -executionpolicy bypass .\install.ps1 -InstallParam $($RMMApp.PackageName)"
                $UninstallCommandLine = 'powershell.exe -executionpolicy bypass .\uninstall.ps1'
            }
            'Huntress' {
                $installcommandline = "powershell.exe -executionpolicy bypass .\install.ps1 -OrgKey $($InstallParams.Orgkey["$($tenant.customerId)"]) -acctkey $($InstallParams.AccountKey)"
                $UninstallCommandLine = 'powershell.exe -executionpolicy bypass .\install.ps1 -Uninstall'
            }
            'Immybot' {
                $installcommandline = "powershell.exe -executionpolicy bypass .\install.ps1 -url $($InstallParams.ClientURL["$($tenant.customerId)"])"
                $UninstallCommandLine = 'powershell.exe -executionpolicy bypass .\uninstall.ps1'
            }
            'syncro' {
                $installcommandline = "powershell.exe -executionpolicy bypass .\install.ps1 -URL $($InstallParams.ClientURL["$($tenant.customerId)"])"
                $UninstallCommandLine = 'powershell.exe -executionpolicy bypass .\uninstall.ps1'
            }
            'NCentral' {
                $installcommandline = "powershell.exe -executionpolicy bypass .\install.ps1 -InstallParam $($RMMApp.PackageName)"
                $UninstallCommandLine = 'powershell.exe -executionpolicy bypass .\uninstall.ps1'
            }
            'automate' {
                $installcommandline = "c:\windows\sysnative\windowspowershell\v1.0\powershell.exe -executionpolicy bypass .\install.ps1 -Server $($InstallParams.Server) -InstallerToken $($InstallParams.InstallerToken["$($tenant.customerId)"]) -LocationID $($InstallParams.LocationID["$($tenant.customerId)"])"
                $UninstallCommandLine = "c:\windows\sysnative\windowspowershell\v1.0\powershell.exe -executionpolicy bypass .\uninstall.ps1 -Server $($InstallParams.Server)"
                $DetectionScript = (Get-Content 'AddMSPApp\automate.detection.ps1' -Raw) -replace '##SERVER##', $InstallParams.Server
                $intuneBody.detectionRules[0].scriptContent = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($DetectionScript))
            }
            'cwcommand' {
                $installcommandline = "powershell.exe -executionpolicy bypass .\install.ps1 -Url $($InstallParams.ClientURL["$($tenant.customerId)"])"
                $UninstallCommandLine = 'powershell.exe -executionpolicy bypass .\uninstall.ps1'
            }
        }
        $intuneBody.installCommandLine = $installcommandline
        $intuneBody.UninstallCommandLine = $UninstallCommandLine


        try {
            $CompleteObject = [PSCustomObject]@{
                tenant          = $tenant.defaultDomainName
                Applicationname = $RMMApp.DisplayName
                assignTo        = $assignTo
                IntuneBody      = $intunebody
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
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant.defaultDomainName -message "MSP Application $($intunebody.Displayname) added to queue" -Sev 'Info'
        } catch {
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant.defaultDomainName -message "Failed to add MSP Application $($intunebody.Displayname) to queue" -Sev 'Error'
            "Failed to add MSP app for $($Tenant.defaultDomainName) to queue"
        }
    }

    $body = [pscustomobject]@{'Results' = $results }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
