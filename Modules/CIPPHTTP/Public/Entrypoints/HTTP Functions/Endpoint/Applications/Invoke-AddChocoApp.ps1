function Invoke-AddChocoApp {
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


    $ChocoApp = $Request.Body
    $intuneBody = Get-Content 'AddChocoApp\Choco.app.json' | ConvertFrom-Json
    $AssignTo = $Request.Body.AssignTo -eq 'customGroup' ? $Request.Body.CustomGroup : $Request.Body.AssignTo
    $intuneBody.description = $ChocoApp.description
    $intuneBody.displayName = $ChocoApp.ApplicationName
    $intuneBody.installExperience.runAsAccount = if ($ChocoApp.InstallAsSystem) { 'system' } else { 'user' }
    $intuneBody.installExperience.deviceRestartBehavior = if ($ChocoApp.DisableRestart) { 'suppress' } else { 'allow' }
    $intuneBody.installCommandLine = "powershell.exe -ExecutionPolicy Bypass .\Install.ps1 -InstallChoco -Packagename $($ChocoApp.PackageName)"
    if ($ChocoApp.customrepo) {
        $intuneBody.installCommandLine = $intuneBody.installCommandLine + " -CustomRepo $($ChocoApp.CustomRepo)"
    }
    if ($ChocoApp.customArguments) {
        $intuneBody.installCommandLine = $intuneBody.installCommandLine + " -CustomArguments '$($ChocoApp.customArguments)'"
    }
    $intuneBody.UninstallCommandLine = "powershell.exe -ExecutionPolicy Bypass .\Uninstall.ps1 -Packagename $($ChocoApp.PackageName)"
    $intuneBody.detectionRules[0].path = "$($ENV:SystemDrive)\programdata\chocolatey\lib"
    $intuneBody.detectionRules[0].fileOrFolderName = "$($ChocoApp.PackageName)"

    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
    $Tenants = ($Request.Body.selectedTenants | Where-Object { $AllowedTenants -contains $_.customerId -or $AllowedTenants -contains 'AllTenants' }).defaultDomainName

    $Results = foreach ($Tenant in $Tenants) {
        try {
            # Apply CIPP text replacement for tenant-specific variables
            $TenantIntuneBody = $intuneBody | ConvertTo-Json -Depth 15 | ConvertFrom-Json
            if ($TenantIntuneBody.installCommandLine -match '%') {
                $TenantIntuneBody.installCommandLine = Get-CIPPTextReplacement -TenantFilter $Tenant -Text $TenantIntuneBody.installCommandLine
            }

            $CompleteObject = [PSCustomObject]@{
                tenant             = $Tenant
                ApplicationName    = $ChocoApp.ApplicationName
                assignTo           = $AssignTo
                InstallationIntent = $Request.Body.InstallationIntent
                IntuneBody         = $TenantIntuneBody
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

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })
}
