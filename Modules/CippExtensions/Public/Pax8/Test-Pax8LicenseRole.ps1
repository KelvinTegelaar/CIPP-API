function Test-Pax8LicenseRole {
    param(
        $Headers
    )

    if ($Headers) {
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $ExtensionConfig = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json
        $Config = $ExtensionConfig.Pax8

        $AllowedRoles = $Config.AllowedCustomRoles.value
        if ($AllowedRoles -and $Headers.'x-ms-client-principal') {
            $UserRoles = Get-CIPPAccessRole -Headers $Headers
            $Allowed = $false
            foreach ($Role in $UserRoles) {
                if ($AllowedRoles -contains $Role) {
                    Write-Information "User has allowed CIPP role: $Role"
                    $Allowed = $true
                    break
                }
            }
            if (-not $Allowed) {
                throw 'This user is not allowed to modify Pax8 subscriptions.'
            }
        }
    }
}
