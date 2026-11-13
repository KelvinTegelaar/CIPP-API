function Get-CIPPTemplateLink {
    <#
    .SYNOPSIS
        Lists the templates a stored template links by GUID.
    .DESCRIPTION
        A Conditional Access template links the Global Secure Access security profile template its
        session control applies, and a security profile template links its filtering policy
        templates. Exports and repo pushes use this so linked templates travel with the template.
        Returns one object per link: Partition, Ref (the linked template's GUID) and Label.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$PartitionKey,
        # The template's parsed JSON
        $Template
    )

    switch ($PartitionKey) {
        'CATemplate' {
            $Link = $Template.sessionControls.globalSecureAccessFilteringProfile.profileId
            if ($Link.value) { [pscustomobject]@{ Partition = 'GSASecurityProfileTemplate'; Ref = "$($Link.value)"; Label = "$($Link.label)" } }
        }
        'GSASecurityProfileTemplate' {
            foreach ($Link in @($Template.policies)) {
                if ($Link.policy.value) { [pscustomobject]@{ Partition = 'GSAFilteringPolicyTemplate'; Ref = "$($Link.policy.value)"; Label = "$($Link.policy.label)" } }
            }
        }
    }
}
