function Test-CIPPSharePointLibraryCopyFolderName {
    <#
    .SYNOPSIS
        Validates and normalises the optional destination folder name for a library copy.
    .DESCRIPTION
        Returns Valid, the trimmed Name and a Reason when invalid. The name becomes a single folder at the
        root of the destination library, so path separators and characters SharePoint refuses are rejected
        up front rather than surfacing as an opaque Graph or CreateCopyJobs error.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$FolderName
    )

    $Name = ([string]$FolderName).Trim()

    if ([string]::IsNullOrEmpty($Name) -or $Name -match '^[\s\.]+$') {
        return [PSCustomObject]@{ Valid = $false; Name = $Name; Reason = 'DestFolderName must contain at least one character that is not a dot or whitespace.' }
    }
    if ($Name.Length -gt 255) {
        return [PSCustomObject]@{ Valid = $false; Name = $Name; Reason = 'DestFolderName must be 255 characters or fewer.' }
    }
    if ($Name -match '["*:<>?/\\|]' -or $Name -match '[\x00-\x1F]') {
        return [PSCustomObject]@{ Valid = $false; Name = $Name; Reason = 'DestFolderName cannot contain path separators, control characters or any of: " * : < > ? / \ |' }
    }
    if ($Name.StartsWith('~$') -or $Name -match '_vti_') {
        return [PSCustomObject]@{ Valid = $false; Name = $Name; Reason = "DestFolderName cannot start with '~$' or contain '_vti_'." }
    }

    $ReservedNames = @(
        'Forms'
        '.lock'
        'desktop.ini'
        'CON', 'PRN', 'AUX', 'NUL'
        'COM0', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9'
        'LPT0', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9'
    )
    if ($Name -in $ReservedNames) {
        return [PSCustomObject]@{ Valid = $false; Name = $Name; Reason = "DestFolderName '$Name' is reserved by SharePoint." }
    }

    return [PSCustomObject]@{ Valid = $true; Name = $Name; Reason = $null }
}
