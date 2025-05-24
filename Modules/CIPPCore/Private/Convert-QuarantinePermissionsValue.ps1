function Convert-QuarantinePermissionsValue {
    param (
        [Parameter(Mandatory = $true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript(
            {$_ -is [String] ? $true : $_ -is [Hashtable] ? $true : $false},
            ErrorMessage = "Input must be a string or hashtable."
            )]
        $InputObject
    )

    #Converts string value with EndUserQuarantinePermissions received from Get-QuarantinePolicy
    if ($InputObject -is [String]) {
        try {
            # Remove square brackets and split into lines
            $InputObject = $InputObject.Trim('[', ']')
            $hashtable = @{}
            $InputObject -split "`n" | ForEach-Object {
                $key, $value = $_ -split ":\s*"
                $hashtable[$key.Trim()] = [System.Convert]::ToBoolean($value.Trim())
            }
            return $hashtable
        }
        catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            throw "Convert-QuarantinePermissionsValue: Failed to convert string to hashtable. Error: $ErrorMessage"
        }
    }

    #Converts hashtable with selected end user quarantine permissions to decimal value used by EndUserQuarantinePermissionsValue property in New-QuarantinePolicy and Set-QuarantinePolicy
    elseif ($InputObject -is [Hashtable]) {
        try {
            $EndUserQuarantinePermissionsValue = 0
            $EndUserQuarantinePermissionsValue += ([int]$InputObject.PermissionToViewHeader ?? 0 ) * 128
            $EndUserQuarantinePermissionsValue += ([int]$InputObject.PermissionToDownload ?? 0 ) * 64
            $EndUserQuarantinePermissionsValue += [int]$InputObject.PermissionToAllowSender * 32
            $EndUserQuarantinePermissionsValue += [int]$InputObject.PermissionToBlockSender * 16
            $EndUserQuarantinePermissionsValue += [int]$InputObject.PermissionToRequestRelease * 8
            $EndUserQuarantinePermissionsValue += [int]$InputObject.PermissionToRelease * 4
            $EndUserQuarantinePermissionsValue += [int]$InputObject.PermissionToPreview * 2
            $EndUserQuarantinePermissionsValue += [int]$InputObject.PermissionToDelete * 1
            return $EndUserQuarantinePermissionsValue
        }
        catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            throw "Convert-QuarantinePermissionsValue: Failed to convert hashtable to QuarantinePermissionsValue. Error: $ErrorMessage"
        }
    }
}
