function Set-CIPPDBCacheExoMailContacts {
    <#
    .SYNOPSIS
        Caches Exchange Online Mail Contacts

    .DESCRIPTION
        Unified collector serving both the DeployMailContact and DeployContactTemplates
        baselines. Get-MailContact carries the mail-specific properties (ExternalEmailAddress,
        MailTip, HiddenFromAddressListsEnabled) while the extended directory properties
        (FirstName, Company, City, Phone, etc.) only exist on Get-Contact, so both are fetched
        (each $select-projected to only the stored fields) and merged per contact.

        ExternalEmailAddress is normalized: the 'SMTP:'/'smtp:' prefix is stripped and the value
        lowercased, because Exchange re-cases the domain part when it creates a contact
        (support@mydomain.com becomes support@Mydomain.com) — the old DeployMailContact standard
        lowercased both sides of the compare for exactly this reason.

    .PARAMETER TenantFilter
        The tenant to cache mail contacts for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Mail Contacts' -sev Debug

        $MailContactResults = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailContact' -cmdParams @{ ResultSize = 'Unlimited' } -Select 'Identity,Guid,ExternalDirectoryObjectId,DisplayName,ExternalEmailAddress,MailTip,HiddenFromAddressListsEnabled')
        $ContactResults = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Contact' -cmdParams @{ ResultSize = 'Unlimited' } -Select 'Identity,FirstName,LastName,Company,StateOrProvince,StreetAddress,Phone,WebPage,Title,City,PostalCode,CountryOrRegion,MobilePhone')
        $ContactByDirectoryId = @{}
        $ContactByIdentity = @{}
        foreach ($Contact in $ContactResults) {
            if ($Contact.ExternalDirectoryObjectId) {
                $ContactByDirectoryId[[string]$Contact.ExternalDirectoryObjectId] = $Contact
            }
            if ($Contact.Identity) {
                $ContactByIdentity[[string]$Contact.Identity] = $Contact
            }
        }

        $MailContacts = [System.Collections.Generic.List[PSObject]]::new()
        foreach ($MailContact in $MailContactResults) {
            $MatchedContact = $null
            if ($MailContact.ExternalDirectoryObjectId -and $ContactByDirectoryId.ContainsKey([string]$MailContact.ExternalDirectoryObjectId)) {
                $MatchedContact = $ContactByDirectoryId[[string]$MailContact.ExternalDirectoryObjectId]
            } elseif ($MailContact.Identity -and $ContactByIdentity.ContainsKey([string]$MailContact.Identity)) {
                $MatchedContact = $ContactByIdentity[[string]$MailContact.Identity]
            }

            $MailContacts.Add([PSCustomObject]@{
                    Identity                      = $MailContact.Identity
                    Guid                          = $MailContact.Guid
                    ExternalDirectoryObjectId     = $MailContact.ExternalDirectoryObjectId
                    DisplayName                   = $MailContact.DisplayName
                    ExternalEmailAddress          = ([string]($MailContact.ExternalEmailAddress -replace '^SMTP:', '' -replace '^smtp:', '')).ToLower()
                    MailTip                       = $MailContact.MailTip
                    HiddenFromAddressListsEnabled = $MailContact.HiddenFromAddressListsEnabled
                    FirstName                     = $MatchedContact.FirstName
                    LastName                      = $MatchedContact.LastName
                    Company                       = $MatchedContact.Company
                    StateOrProvince               = $MatchedContact.StateOrProvince
                    StreetAddress                 = $MatchedContact.StreetAddress
                    Phone                         = $MatchedContact.Phone
                    WebPage                       = $MatchedContact.WebPage
                    Title                         = $MatchedContact.Title
                    City                          = $MatchedContact.City
                    PostalCode                    = $MatchedContact.PostalCode
                    CountryOrRegion               = $MatchedContact.CountryOrRegion
                    MobilePhone                   = $MatchedContact.MobilePhone
                })
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ExoMailContacts' -Data @($MailContacts) -AddCount
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($MailContacts.Count) Mail Contacts" -sev Debug

        $MailContactResults = $null
        $ContactResults = $null
        $ContactByDirectoryId = $null
        $ContactByIdentity = $null
        $MailContacts = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Mail Contacts: $($_.Exception.Message)" -sev Error
    }
}
