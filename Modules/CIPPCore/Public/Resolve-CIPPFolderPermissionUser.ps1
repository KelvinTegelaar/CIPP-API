function Resolve-CIPPFolderPermissionUser {
    <#
    .SYNOPSIS
        Resolve an Exchange folder-permission User value to SMTP/UPN/object ID candidates.

    .DESCRIPTION
        Get-MailboxFolderPermission often returns display names. Duplicate display names
        (e.g. licensed + unlicensed accounts) cause Remove/Set-MailboxFolderPermission to
        bind the wrong principal and throw UserNotFoundInPermissionEntryException.

        This helper resolves display names via Graph (users + groups) and returns ordered
        identity candidates for remove/set retries, plus enrichment fields for list APIs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        $User,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $SystemUsers = @('Default', 'Anonymous', 'NT AUTHORITY\SELF')

    # Normalize EXO User objects / arrays to a string
    $UserString = $null
    if ($null -eq $User -or $User -eq '') {
        return [PSCustomObject]@{
            User             = $null
            UserEmail        = $null
            UserId           = $null
            UserAmbiguous    = $false
            IsSystemUser     = $false
            Candidates       = @()
            CandidateEmails  = @()
        }
    }

    if ($User -is [System.Collections.IEnumerable] -and $User -isnot [string]) {
        $First = @($User) | Select-Object -First 1
        if ($First -is [psobject] -and ($First.PSObject.Properties.Name -contains 'DisplayName' -or $First.PSObject.Properties.Name -contains 'UserId')) {
            $UserString = $First.DisplayName ?? $First.UserId ?? [string]$First
        } else {
            $UserString = [string]$First
        }
    } elseif ($User -is [psobject] -and -not ($User -is [string])) {
        $UserString = $User.DisplayName ?? $User.UserId ?? $User.userPrincipalName ?? $User.mail ?? [string]$User
    } else {
        $UserString = [string]$User
    }

    $UserString = $UserString.Trim()

    if ($UserString -in $SystemUsers) {
        return [PSCustomObject]@{
            User             = $UserString
            UserEmail        = $null
            UserId           = $null
            UserAmbiguous    = $false
            IsSystemUser     = $true
            Candidates       = @($UserString)
            CandidateEmails  = @()
        }
    }

    $Candidates = [System.Collections.Generic.List[string]]::new()
    $CandidateEmails = [System.Collections.Generic.List[string]]::new()
    $ResolvedId = $null
    $ResolvedEmail = $null
    $Ambiguous = $false

    $AddCandidate = {
        param([string]$Value)
        if ([string]::IsNullOrWhiteSpace($Value)) { return }
        if (-not $Candidates.Contains($Value)) {
            $Candidates.Add($Value)
        }
    }

    $AddEmail = {
        param([string]$Value)
        if ([string]::IsNullOrWhiteSpace($Value)) { return }
        if (-not $CandidateEmails.Contains($Value)) {
            $CandidateEmails.Add($Value)
        }
    }

    # Prefer the original value first when it is already an email or GUID
    & $AddCandidate $UserString
    if ($UserString -match '@') {
        $ResolvedEmail = $UserString
        & $AddEmail $UserString
        try {
            $DirectUser = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$([System.Uri]::EscapeDataString($UserString))?`$select=id,displayName,userPrincipalName,mail,accountEnabled,assignedLicenses" -tenantid $TenantFilter -NoAuthCheck $true
            if ($DirectUser.id) {
                $ResolvedId = $DirectUser.id
                & $AddCandidate $DirectUser.id
                & $AddCandidate $DirectUser.userPrincipalName
                & $AddCandidate $DirectUser.mail
                & $AddEmail $DirectUser.userPrincipalName
                & $AddEmail $DirectUser.mail
            }
        } catch {
            Write-Information "Could not resolve folder permission user by email '$UserString': $($_.Exception.Message)"
        }
    } elseif ($UserString -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
        $ResolvedId = $UserString
        try {
            $DirectUser = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$UserString?`$select=id,displayName,userPrincipalName,mail,accountEnabled,assignedLicenses" -tenantid $TenantFilter -NoAuthCheck $true
            if ($DirectUser.id) {
                & $AddCandidate $DirectUser.userPrincipalName
                & $AddCandidate $DirectUser.mail
                & $AddEmail $DirectUser.userPrincipalName
                & $AddEmail $DirectUser.mail
                $ResolvedEmail = $DirectUser.mail ?? $DirectUser.userPrincipalName
            }
        } catch {
            Write-Information "Could not resolve folder permission user by id '$UserString': $($_.Exception.Message)"
        }
    } else {
        # Display name (or other non-email identifier) — look up users and groups
        $EscapedName = $UserString -replace "'", "''"
        $MatchedPrincipals = [System.Collections.Generic.List[object]]::new()

        try {
            $GraphUsers = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users?`$filter=displayName eq '$EscapedName'&`$select=id,displayName,userPrincipalName,mail,accountEnabled,assignedLicenses" -tenantid $TenantFilter -NoAuthCheck $true
            foreach ($GraphUser in @($GraphUsers)) {
                if ($GraphUser.id) {
                    $LicenseCount = @($GraphUser.assignedLicenses).Count
                    $MatchedPrincipals.Add([PSCustomObject]@{
                            Type             = 'User'
                            Id               = $GraphUser.id
                            Mail             = $GraphUser.mail
                            UserPrincipalName = $GraphUser.userPrincipalName
                            AccountEnabled   = [bool]$GraphUser.accountEnabled
                            LicenseCount     = $LicenseCount
                        })
                }
            }
        } catch {
            Write-Information "Could not search users by display name '$UserString': $($_.Exception.Message)"
        }

        try {
            $GraphGroups = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/groups?`$filter=displayName eq '$EscapedName'&`$select=id,displayName,mail,mailEnabled,securityEnabled" -tenantid $TenantFilter -NoAuthCheck $true
            foreach ($GraphGroup in @($GraphGroups)) {
                if ($GraphGroup.id) {
                    $MatchedPrincipals.Add([PSCustomObject]@{
                            Type              = 'Group'
                            Id                = $GraphGroup.id
                            Mail              = $GraphGroup.mail
                            UserPrincipalName = $GraphGroup.mail
                            AccountEnabled    = $true
                            LicenseCount      = 1
                        })
                }
            }
        } catch {
            Write-Information "Could not search groups by display name '$UserString': $($_.Exception.Message)"
        }

        if ($MatchedPrincipals.Count -gt 1) {
            $Ambiguous = $true
        }

        # Prefer enabled + licensed users first — those usually own the working ACE
        $Ordered = $MatchedPrincipals | Sort-Object -Property `
        @{ Expression = { if ($_.Type -eq 'User') { 0 } else { 1 } } },
        @{ Expression = { -not $_.AccountEnabled } },
        @{ Expression = { $_.LicenseCount -eq 0 } }

        foreach ($Principal in $Ordered) {
            & $AddCandidate $Principal.Id
            & $AddCandidate $Principal.UserPrincipalName
            & $AddCandidate $Principal.Mail
            & $AddEmail $Principal.UserPrincipalName
            & $AddEmail $Principal.Mail

            if (-not $Ambiguous) {
                $ResolvedId = $Principal.Id
                $ResolvedEmail = $Principal.Mail ?? $Principal.UserPrincipalName
            }
        }
    }

    return [PSCustomObject]@{
        User            = $UserString
        UserEmail       = $ResolvedEmail
        UserId          = $ResolvedId
        UserAmbiguous   = $Ambiguous
        IsSystemUser    = $false
        Candidates      = @($Candidates)
        CandidateEmails = @($CandidateEmails | Where-Object { $_ -match '@' })
    }
}
