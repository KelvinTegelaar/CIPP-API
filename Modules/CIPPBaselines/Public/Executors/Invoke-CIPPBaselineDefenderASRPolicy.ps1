function Invoke-CIPPBaselineDefenderASRPolicy {
    <#
    .SYNOPSIS
        DefenderASRPolicy executor: recreates the 'ASR Default rules' settings catalog policy.
    .DESCRIPTION
        The classic's write: delete the drifted policy, then recreate through the
        Set-CIPPDefenderASRPolicy helper which owns the rules group and the assignment.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    if (-not [string]::IsNullOrWhiteSpace("$($Current.policyId)")) {
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies('$($Current.policyId)')" -tenantid $TenantFilter -type DELETE
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Deleted the drifted Defender ASR policy for recreation.' -Sev 'Info'
    }

    $Pick = { param($Value, $Default) [string]($Value.value ?? $Value ?? $Default) }
    $ASRSettings = @{
        Mode                    = (& $Pick $Remediate.mode 'block')
        BlockObfuscatedScripts  = [bool]$Remediate.blockObfuscatedScripts
        BlockAdobeChild         = [bool]$Remediate.blockAdobeChild
        BlockWin32Macro         = [bool]$Remediate.blockWin32Macro
        BlockCredentialStealing = [bool]$Remediate.blockCredentialStealing
        BlockPSExec             = [bool]$Remediate.blockPSExec
        WMIPersistence          = [bool]$Remediate.wmiPersistence
        BlockSystemTools        = [bool]$Remediate.blockSystemTools
        BlockOfficeExes         = [bool]$Remediate.blockOfficeExes
        BlockOfficeApps         = [bool]$Remediate.blockOfficeApps
        BlockSafeMode           = [bool]$Remediate.blockSafeMode
        BlockYoungExe           = [bool]$Remediate.blockYoungExe
        blockJSVB               = [bool]$Remediate.blockJSVB
        BlockWebshellForServers = [bool]$Remediate.blockWebshellForServers
        blockOfficeComChild     = [bool]$Remediate.blockOfficeComChild
        blockOfficeChild        = [bool]$Remediate.blockOfficeChild
        BlockUntrustedUSB       = [bool]$Remediate.blockUntrustedUSB
        EnableRansomwareVac     = [bool]$Remediate.enableRansomwareVac
        BlockExesMail           = [bool]$Remediate.blockExesMail
        BlockUnsignedDrivers    = [bool]$Remediate.blockUnsignedDrivers
        AssignTo                = (& $Pick $Remediate.assignTo 'none')
    }

    $Result = Set-CIPPDefenderASRPolicy -TenantFilter $TenantFilter -ASR $ASRSettings -APIName 'Baselines'
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "$Result" -Sev 'Info'
}
