using namespace System.Net

Function Invoke-AddChocoApp {
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

    $ChocoApp = $Request.Body
    $intuneBody = Get-Content 'AddChocoApp\choco.app.json' | ConvertFrom-Json
    $AssignTo = $Request.Body.AssignTo
    $intuneBody.description = $ChocoApp.description
    $intuneBody.displayName = $ChocoApp.ApplicationName
    $intuneBody.installExperience.runAsAccount = if ($ChocoApp.InstallAsSystem) { 'system' } else { 'user' }
    $intuneBody.installExperience.deviceRestartBehavior = if ($ChocoApp.DisableRestart) { 'suppress' } else { 'allow' }
    $intuneBody.installCommandLine = "powershell.exe -ExecutionPolicy Bypass .\Install.ps1 -InstallChoco -Packagename $($ChocoApp.PackageName)"
    if ($ChocoApp.customrepo) {
        $intuneBody.installCommandLine = $intuneBody.installCommandLine + " -CustomRepo $($ChocoApp.CustomRepo)"
    }
    $intuneBody.UninstallCommandLine = "powershell.exe -ExecutionPolicy Bypass .\Uninstall.ps1 -Packagename $($ChocoApp.PackageName)"
    $intuneBody.detectionRules[0].path = "$($ENV:SystemDrive)\programdata\chocolatey\lib"
    $intuneBody.detectionRules[0].fileOrFolderName = "$($ChocoApp.PackageName)"

    $Tenants = $Request.Body.selectedTenants.defaultDomainName
    $Results = foreach ($Tenant in $Tenants) {
        try {
            $CompleteObject = [PSCustomObject]@{
                tenant             = $Tenant
                ApplicationName    = $ChocoApp.ApplicationName
                assignTo           = $AssignTo
                InstallationIntent = $Request.Body.InstallationIntent
                IntuneBody         = $intuneBody
            } | ConvertTo-Json -Depth 15
            $Table = Get-CippTable -tablename 'apps'
            $Table.Force = $true
            Add-CIPPAzDataTableEntity @Table -Entity @{
                JSON         = "$CompleteObject"
                RowKey       = "$((New-Guid).GUID)"
                PartitionKey = 'apps'
            }
            "Successfully added Choco App for $($Tenant) to queue."
            Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant -message "Successfully added Choco App $($intuneBody.DisplayName) to queue" -Sev 'Info'
        } catch {
            "Failed adding Choco App for $($Tenant) to queue"
            Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant -message "Failed to add Chocolatey Application $($intuneBody.DisplayName) to queue" -Sev 'Error'
        }
    }

    $body = [PSCustomObject]@{'Results' = $Results }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })
}
