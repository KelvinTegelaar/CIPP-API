function Convert-QuarantinePermissionsValue {
    [CmdletBinding(DefaultParameterSetName = 'DecimalValue')]
    param (
        [Parameter(Mandatory, Position = 0, ParameterSetName = "StringValue")]
        [ValidateNotNullOrEmpty()]
        [string]$InputObject,

        [Parameter(Position = 0, ParameterSetName = "DecimalValue")]
        [int]$PermissionToViewHeader = 0,
        [Parameter(Position = 1, ParameterSetName = "DecimalValue")]
        [int]$PermissionToDownload = 0,
        [Parameter(Mandatory, Position = 2, ParameterSetName = "DecimalValue")]
        [int]$PermissionToAllowSender,
        [Parameter(Mandatory, Position = 3, ParameterSetName = "DecimalValue")]
        [int]$PermissionToBlockSender,
        [Parameter(Mandatory, Position = 4, ParameterSetName = "DecimalValue")]
        [int]$PermissionToRequestRelease,
        [Parameter(Mandatory, Position = 5, ParameterSetName = "DecimalValue")]
        [int]$PermissionToRelease,
        [Parameter(Mandatory, Position = 6, ParameterSetName = "DecimalValue")]
        [int]$PermissionToPreview,
        [Parameter(Mandatory, Position = 7, ParameterSetName = "DecimalValue")]
        [int]$PermissionToDelete
    )

    #Converts string value with EndUserQuarantinePermissions received from Get-QuarantinePolicy
    if (($PSCmdlet.ParameterSetName) -eq "StringValue") {
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
            throw "Convert-QuarantinePermissionsValue: Failed to convert string to hashtable."
        }
    }

    #Converts selected end user quarantine permissions to decimal value used by EndUserQuarantinePermissionsValue property in New-QuarantinePolicy and Set-QuarantinePolicy
    elseif (($PSCmdlet.ParameterSetName) -eq "DecimalValue") {
        try {
            # both PermissionToRequestRelease and PermissionToRelease cannot be set to true at the same time
            if($PermissionToRequestRelease -eq 1 -and $PermissionToRelease -eq 1) {
                throw "PermissionToRequestRelease and PermissionToRelease cannot both be set to true."
            }

            # Convert each permission to a binary string
            $BinaryValue = [string]@(
                $PermissionToViewHeader,
                $PermissionToDownload,
                $PermissionToAllowSender,
                $PermissionToBlockSender,
                $PermissionToRequestRelease,
                $PermissionToRelease,
                $PermissionToPreview,
                $PermissionToDelete
            ) -replace '\s',''

            # Convert the binary string to an Decimal value
            return [convert]::ToInt32($BinaryValue,2)
        }
        catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            throw "Convert-QuarantinePermissionsValue: Failed to convert QuarantinePermissions to QuarantinePermissionsValue. Error: $ErrorMessage"
        }
    }
}
