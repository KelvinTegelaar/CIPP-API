function Invoke-CIPPStandardDisableSelfServiceLicenses {
    <#
    .FUNCTIONALITY
    Internal
    .APINAME
    DisableSelfServiceLicenses
    .CAT
    Entra (AAD) Standards
    .TAG
    "mediumimpact"
    .HELPTEXT
    This standard currently does not function and can be safely disabled
    .ADDEDCOMPONENT
    .LABEL
    Disable Self Service Licensing
    .IMPACT
    Medium Impact
    .POWERSHELLEQUIVALENT
    Set-MsolCompanySettings -AllowAdHocSubscriptions $false
    .RECOMMENDEDBY
    .DOCSDESCRIPTION
    This standard currently does not function and can be safely disabled
    .UPDATECOMMENTBLOCK
    Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    #>




    param($Tenant, $Settings)

    Write-LogMessage -API 'Standards' -tenant $tenant -message 'Self Service Licenses cannot be disabled' -sev Error

}




