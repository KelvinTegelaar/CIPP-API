function Get-CIPPMSPAppInstallCommand {
    <#
    .SYNOPSIS
        Builds the install/uninstall command lines for an MSP RMM app for a single tenant.
    .DESCRIPTION
        Shared by Invoke-AddMSPApp (manual/queue deploy) and New-CIPPIntuneAppDeployment
        (the 'Deploy Intune Application Template' standard). Each parameter value may be:
          - a flat string, optionally containing %CIPP variables% that resolve per-tenant
            (Application Template shape), or
          - an object keyed by tenant customerId (legacy per-tenant deploy shape).
        Values are resolved for the tenant, run through Get-CIPPTextReplacement so any
        %variables% are substituted with the tenant's value, then escaped with
        ConvertTo-CIPPSafePwshArg before being placed on the command line.
    .PARAMETER RmmName
        The MSP tool identifier (datto, syncro, Huntress, automate, cwcommand, ninja, NCentral).
    .PARAMETER Params
        The params object from the app config / request body.
    .PARAMETER Tenant
        The tenant object, requires customerId and defaultDomainName.
    .PARAMETER PackageName
        Package name for ninja/NCentral installs (not stored under params).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RmmName,

        $Params,

        [Parameter(Mandatory = $true)]
        $Tenant,

        [string]$PackageName
    )

    $InstallParams = [PSCustomObject]$Params

    # Resolve a raw parameter value for this tenant: pick the per-tenant keyed value when the
    # value is an object (legacy shape), otherwise use it as-is (template shape), then replace
    # any %CIPP variables% using the tenant context. Returns the raw (unescaped) string.
    function Resolve-MSPValue {
        param($Value)
        if ($null -eq $Value) { return '' }
        if ($Value -is [string]) {
            $Resolved = $Value
        } elseif ($Value -is [System.Collections.IDictionary]) {
            $Resolved = [string]$Value[$Tenant.customerId]
        } elseif ($Value -is [pscustomobject]) {
            $Resolved = [string]$Value.$($Tenant.customerId)
        } else {
            $Resolved = [string]$Value
        }
        if ($Resolved -match '%') {
            $Resolved = Get-CIPPTextReplacement -TenantFilter $Tenant.defaultDomainName -Text $Resolved
        }
        return $Resolved
    }

    $DetectionScriptContent = $null

    switch ($RmmName) {
        'datto' {
            $DattoUrl = ConvertTo-CIPPSafePwshArg -Value (Resolve-MSPValue $InstallParams.DattoURL)
            $DattoGuid = ConvertTo-CIPPSafePwshArg -Value (Resolve-MSPValue $InstallParams.DattoGUID)
            $installCommandLine = "powershell.exe -ExecutionPolicy Bypass .\install.ps1 -URL $DattoUrl -GUID $DattoGuid"
            $uninstallCommandLine = 'powershell.exe -ExecutionPolicy Bypass .\uninstall.ps1'
        }
        'ninja' {
            $NinjaPackage = ConvertTo-CIPPSafePwshArg -Value ([string]$PackageName)
            $installCommandLine = "powershell.exe -ExecutionPolicy Bypass .\install.ps1 -InstallParam $NinjaPackage"
            $uninstallCommandLine = 'powershell.exe -ExecutionPolicy Bypass .\uninstall.ps1'
        }
        'Huntress' {
            $HuntressOrgKey = ConvertTo-CIPPSafePwshArg -Value (Resolve-MSPValue $InstallParams.Orgkey)
            $HuntressAccountKey = ConvertTo-CIPPSafePwshArg -Value (Resolve-MSPValue $InstallParams.AccountKey)
            $installCommandLine = "powershell.exe -ExecutionPolicy Bypass .\install.ps1 -OrgKey $HuntressOrgKey -acctkey $HuntressAccountKey"
            $uninstallCommandLine = 'powershell.exe -ExecutionPolicy Bypass .\install.ps1 -Uninstall'
        }
        'syncro' {
            $SyncroUrl = ConvertTo-CIPPSafePwshArg -Value (Resolve-MSPValue $InstallParams.ClientURL)
            $installCommandLine = "powershell.exe -ExecutionPolicy Bypass .\install.ps1 -URL $SyncroUrl"
            $uninstallCommandLine = 'powershell.exe -ExecutionPolicy Bypass .\uninstall.ps1'
        }
        'NCentral' {
            $NCentralPackage = ConvertTo-CIPPSafePwshArg -Value ([string]$PackageName)
            $installCommandLine = "powershell.exe -ExecutionPolicy Bypass .\install.ps1 -InstallParam $NCentralPackage"
            $uninstallCommandLine = 'powershell.exe -ExecutionPolicy Bypass .\uninstall.ps1'
        }
        'automate' {
            $ServerRaw = Resolve-MSPValue $InstallParams.Server
            $AutomateServer = ConvertTo-CIPPSafePwshArg -Value $ServerRaw
            $AutomateInstallerToken = ConvertTo-CIPPSafePwshArg -Value (Resolve-MSPValue $InstallParams.InstallerToken)
            $AutomateLocationId = ConvertTo-CIPPSafePwshArg -Value (Resolve-MSPValue $InstallParams.LocationID)
            $installCommandLine = "c:\windows\sysnative\windowspowershell\v1.0\powershell.exe -ExecutionPolicy Bypass .\install.ps1 -Server $AutomateServer -InstallerToken $AutomateInstallerToken -LocationID $AutomateLocationId"
            $uninstallCommandLine = "c:\windows\sysnative\windowspowershell\v1.0\powershell.exe -ExecutionPolicy Bypass .\uninstall.ps1 -Server $AutomateServer"
            $DetectionScriptContent = (Get-Content 'AddMSPApp\automate.detection.ps1' -Raw) -replace '##SERVER##', $ServerRaw
        }
        'cwcommand' {
            $CwClientUrl = ConvertTo-CIPPSafePwshArg -Value (Resolve-MSPValue $InstallParams.ClientURL)
            $installCommandLine = "powershell.exe -ExecutionPolicy Bypass .\install.ps1 -Url $CwClientUrl"
            $uninstallCommandLine = 'powershell.exe -ExecutionPolicy Bypass .\uninstall.ps1'
        }
        default {
            throw "Unknown MSP app type '$RmmName'"
        }
    }

    return [PSCustomObject]@{
        InstallCommandLine     = $installCommandLine
        UninstallCommandLine   = $uninstallCommandLine
        DetectionScriptContent = $DetectionScriptContent
    }
}
