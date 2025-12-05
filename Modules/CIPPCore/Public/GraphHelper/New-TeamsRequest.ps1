function New-TeamsRequest {
    [CmdletBinding()]
    Param(
        $TenantFilter,
        $Cmdlet,
        $CmdParams = @{},
        [switch]$AvailableCmdlets
    )

    if ($AvailableCmdlets) {
        Get-Command -Module MicrosoftTeams | Select-Object Name
        return
    }
    if (Get-Command -Module MicrosoftTeams -Name $Cmdlet) {
        $TeamsToken = (Get-GraphToken -tenantid $TenantFilter -scope '48ac35b8-9aa8-4d74-927d-1f4a14a0b239/.default').Authorization -replace 'Bearer '
        $GraphToken = (Get-GraphToken -tenantid $TenantFilter).Authorization -replace 'Bearer '

        $null = Connect-MicrosoftTeams -AccessTokens @($TeamsToken, $GraphToken)
        & $Cmdlet @CmdParams
    } else {
        Write-Error "Cmdlet $Cmdlet not found in MicrosoftTeams module"
    }
}
