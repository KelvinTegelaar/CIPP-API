function Invoke-ListSharePointExternalUsers {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Lists external/guest users known to SharePoint from two sources: the tenant external
        users store (populated when a guest first redeems a share) and a sweep of every site's
        user list (which also catches guests who were granted membership but never signed in).
        Every entry is classified against Entra: 'Entra B2B' (live Entra guest), 'Orphaned B2B'
        (the Entra guest was deleted but SharePoint still references them) or 'SharePoint-only'
        (legacy email-authenticated guest that never had an Entra object).

        Each row also carries SiteAccess: one entry per site with the site user ID and the
        site-level guest expiration (UserExpiration from the site's User Information List),
        for use with ExecSPOGuestAccess (Extend / Expire on a single site).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter

    # CSOM verbose JSON dates arrive as '/Date(year,month,day,h,m,s,ms)/' with a 0-based month.
    function ConvertFrom-CsomDate($Value) {
        if ("$Value" -match '/Date\((\d+),(\d+),(\d+),(\d+),(\d+),(\d+),(\d+)\)/') {
            return ([datetime]::new([int]$Matches[1], ([int]$Matches[2] + 1), [int]$Matches[3], [int]$Matches[4], [int]$Matches[5], [int]$Matches[6], [System.DateTimeKind]::Utc)).ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
        return $Value
    }

    try {
        # --- Source 1: tenant external users store ---
        try {
            $StoreUsers = @(Get-CIPPSPOExternalUsers -TenantFilter $TenantFilter)
        } catch {
            throw "Could not enumerate the SharePoint external users store: $($_.Exception.Message)"
        }

        # --- Source 2: guest entries in every site's user list ---
        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
        $Scope = "$($SharePointInfo.SharePointUrl)/.default"
        $JsonAccept = @{ Accept = 'application/json;odata=nometadata' }
        $VerboseHeaders = @{ Accept = 'application/json;odata=verbose' }
        # Site guest expiration is stored on the User Information List (UserExpiration);
        # list item ID == site user ID.
        $CamlBody = @{
            query = @{
                __metadata = @{ type = 'SP.CamlQuery' }
                ViewXml    = "<View><ViewFields><FieldRef Name='ID'/><FieldRef Name='UserExpiration'/></ViewFields><RowLimit>5000</RowLimit></View>"
            }
        } | ConvertTo-Json -Depth 5 -Compress
        $SiteGuests = @{}
        try {
            # NB: getAllSites returns an empty set when $select is combined with this $filter.
            $Sites = @((New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/getAllSites?`$filter=isPersonalSite eq false&`$top=999" -tenantid $TenantFilter -AsApp $true).webUrl) | Where-Object { $_ }
        } catch {
            $Sites = @()
            Write-Information "Site enumeration failed; external users report is store-only: $($_.Exception.Message)"
        }

        foreach ($SiteUrl in $Sites) {
            try {
                $Users = New-GraphGetRequest -uri "$($SiteUrl.TrimEnd('/'))/_api/web/siteusers?`$select=Id,Title,Email,LoginName,IsShareByEmailGuestUser,IsEmailAuthenticationGuestUser" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
            } catch {
                continue # sites the app cannot reach (locked etc.) are skipped
            }

            $SiteGuestUsers = @($Users | Where-Object { [bool]$_.IsShareByEmailGuestUser -or [bool]$_.IsEmailAuthenticationGuestUser -or $_.LoginName -match '(?i)#ext#|urn%3aspo%3aguest' })
            if ($SiteGuestUsers.Count -eq 0) { continue }

            # Per-site guest expiration, only fetched for sites that actually have guests.
            $ExpiryById = @{}
            try {
                # NOTE: SharePoint REST app-only POSTs need the certificate-based token; see
                # Remove-CIPPSPOSiteUser for the POST mechanism used for SharePoint REST writes.
                $Resp = New-GraphPOSTRequest -uri "$($SiteUrl.TrimEnd('/'))/_api/web/SiteUserInfoList/GetItems" -tenantid $TenantFilter -scope $Scope -AsApp $true -UseCertificate -type 'POST' -body $CamlBody -contentType 'application/json;odata=verbose' -AddedHeaders $VerboseHeaders
                $Items = if ($Resp.d.results) { $Resp.d.results } elseif ($Resp.value) { $Resp.value } else { @($Resp) }
                foreach ($Item in $Items) {
                    if ($Item.ID) { $ExpiryById[[int]$Item.ID] = $Item.UserExpiration }
                }
            } catch {
                Write-Information "Could not read guest expiration for $($SiteUrl): $($_.Exception.Message)"
            }

            foreach ($User in $SiteGuestUsers) {
                $Key = ($User.LoginName -split '\|')[-1].ToLower()
                if (-not $SiteGuests.ContainsKey($Key)) {
                    $SiteGuests[$Key] = [PSCustomObject]@{
                        Title      = $User.Title
                        Email      = $User.Email
                        LoginName  = $User.LoginName
                        Sites      = [System.Collections.Generic.List[string]]::new()
                        SiteAccess = [System.Collections.Generic.List[object]]::new()
                    }
                }
                [void]$SiteGuests[$Key].Sites.Add($SiteUrl)
                $Expiry = $ExpiryById[[int]$User.Id]
                $SiteGuests[$Key].SiteAccess.Add([PSCustomObject]@{
                        SiteUrl    = $SiteUrl
                        SiteUserId = [int]$User.Id
                        Expiration = if ($Expiry) { $Expiry } else { $null } # null = no expiry set
                    })
            }
        }

        # --- Entra guest sweep for the join ---
        $EntraGuests = @()
        if ($StoreUsers.Count -gt 0 -or $SiteGuests.Count -gt 0) {
            try {
                $EntraGuests = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users?`$filter=userType eq 'Guest'&`$select=id,userPrincipalName,mail&`$top=999" -tenantid $TenantFilter -AsApp $true)
            } catch {
                throw "Could not list Entra guest users for cross-referencing: $($_.Exception.Message)"
            }
        }
        $GuestsByUpn = @{}
        $GuestsByMail = @{}
        foreach ($Guest in $EntraGuests) {
            if ($Guest.userPrincipalName) { $GuestsByUpn[$Guest.userPrincipalName.ToLower()] = $Guest }
            if ($Guest.mail) { $GuestsByMail[$Guest.mail.ToLower()] = $Guest }
        }

        function Resolve-GuestClassification($LoginName, $AcceptedAs, $InvitedAs) {
            if ("$LoginName" -match '(?i)urn(%3a|:)spo(%3a|:)guest') {
                return @('SharePoint-only (email authenticated)', $null)
            }
            $ClaimsUpn = ("$LoginName" -split '\|')[-1].ToLower()
            $EntraUser = $GuestsByUpn[$ClaimsUpn]
            if (-not $EntraUser -and $AcceptedAs) { $EntraUser = $GuestsByMail[([string]$AcceptedAs).ToLower()] }
            if (-not $EntraUser -and $InvitedAs) { $EntraUser = $GuestsByMail[([string]$InvitedAs).ToLower()] }
            if ($EntraUser) { return @('Entra B2B', $EntraUser) }
            return @('Orphaned B2B (not in Entra)', $null)
        }

        # Soonest site-level expiry across a guest's sites (null when none set), so the
        # list can be sorted by it.
        function Get-NextExpiration($SiteAccess) {
            $Dates = @($SiteAccess | Where-Object { $_.Expiration } | ForEach-Object { [datetime]$_.Expiration })
            if ($Dates.Count -eq 0) { return $null }
            return ($Dates | Sort-Object | Select-Object -First 1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        }

        $Rows = [System.Collections.Generic.List[object]]::new()
        $SeenKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

        foreach ($User in $StoreUsers) {
            $GuestType, $EntraUser = Resolve-GuestClassification $User.LoginName $User.AcceptedAs $User.InvitedAs
            # Match this store entry to any site membership sweep hit for a Sites column.
            $MatchKey = $null
            foreach ($Key in $SiteGuests.Keys) {
                $SG = $SiteGuests[$Key]
                if (($User.AcceptedAs -and $SG.Email -eq $User.AcceptedAs) -or ($EntraUser -and $Key -eq $EntraUser.userPrincipalName.ToLower())) { $MatchKey = $Key; break }
            }
            if ($MatchKey) { [void]$SeenKeys.Add($MatchKey) }
            # Direct assignment keeps the List intact; an if-expression would pipeline-unwrap
            # a single-element list to a scalar and the API would emit a string, not an array.
            $RowSites = [System.Collections.Generic.List[string]]::new()
            $RowSiteAccess = [System.Collections.Generic.List[object]]::new()
            if ($MatchKey) {
                $RowSites = $SiteGuests[$MatchKey].Sites
                $RowSiteAccess = $SiteGuests[$MatchKey].SiteAccess
            }
            $Rows.Add([PSCustomObject]@{
                    DisplayName = $User.DisplayName
                    InvitedAs   = $User.InvitedAs
                    AcceptedAs  = $User.AcceptedAs
                    # Store entries often carry no login; the site sweep's claims login fills the gap.
                    LoginName   = if ($User.LoginName) { $User.LoginName } elseif ($MatchKey) { $SiteGuests[$MatchKey].LoginName } else { $null }
                    UniqueId    = $User.UniqueId
                    WhenCreated = ConvertFrom-CsomDate $User.WhenCreated
                    InvitedBy   = $User.InvitedBy
                    GuestType   = $GuestType
                    InEntra     = [bool]$EntraUser
                    EntraUserId = $EntraUser.id
                    Source      = 'External users store'
                    Sites          = $RowSites
                    SiteAccess     = $RowSiteAccess
                    NextExpiration = Get-NextExpiration $RowSiteAccess
                })
        }

        # Guests that only exist as site members (never redeemed / store aged out)
        foreach ($Key in $SiteGuests.Keys) {
            if ($SeenKeys.Contains($Key)) { continue }
            $SG = $SiteGuests[$Key]
            $GuestType, $EntraUser = Resolve-GuestClassification $SG.LoginName $SG.Email $null
            $Rows.Add([PSCustomObject]@{
                    DisplayName = $SG.Title
                    InvitedAs   = $null
                    AcceptedAs  = $SG.Email
                    LoginName   = $SG.LoginName
                    UniqueId    = $null
                    WhenCreated = $null
                    InvitedBy   = $null
                    GuestType   = $GuestType
                    InEntra     = [bool]$EntraUser
                    EntraUserId = $EntraUser.id
                    Source      = 'Site membership'
                    Sites          = $SG.Sites
                    SiteAccess     = $SG.SiteAccess
                    NextExpiration = Get-NextExpiration $SG.SiteAccess
                })
        }

        $Body = @($Rows)
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Body = "Failed to list SharePoint external users: $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Body }
        })
}