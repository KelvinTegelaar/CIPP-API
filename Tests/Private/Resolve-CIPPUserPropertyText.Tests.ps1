# %property% tokens in a bulk user edit are filled from each user's own Graph properties.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Resolve-CIPPUserPropertyText.ps1')
    $User = [pscustomobject]@{ givenName = 'Jane'; surname = 'Doe'; jobTitle = ''; businessPhones = @('0123', '0456'); companyName = $null }
}

Describe 'Resolve-CIPPUserPropertyText' {
    It 'lists the referenced properties, mapping the FirstName/LastName aliases, without duplicates' {
        $Names = Resolve-CIPPUserPropertyText -Text '%FirstName% %surname% / %givenName% %jobTitle%'
        @($Names | Sort-Object) | Should -Be @('givenName', 'jobTitle', 'surname')
    }

    It 'returns nothing for text without tokens' {
        @(Resolve-CIPPUserPropertyText -Text 'Service Bot').Count | Should -Be 0
        @(Resolve-CIPPUserPropertyText -Text '100% done').Count | Should -Be 0
    }

    It 'fills tokens from the user, matching property names case-insensitively' {
        Resolve-CIPPUserPropertyText -Text '%GIVENNAME% %LastName% (Contoso)' -User $User | Should -Be 'Jane Doe (Contoso)'
    }

    It 'joins multi-value properties' {
        Resolve-CIPPUserPropertyText -Text 'Tel %businessPhones%' -User $User | Should -Be 'Tel 0123, 0456'
    }

    It 'leaves text without tokens unchanged' {
        Resolve-CIPPUserPropertyText -Text 'Service Bot' -User $User | Should -Be 'Service Bot'
    }

    It 'throws, naming every token, when a property has no value' {
        { Resolve-CIPPUserPropertyText -Text '%givenName% %jobTitle% %companyName% %jobTitle%' -User $User } |
            Should -Throw '%jobTitle%, %companyName% has no value for this user'
    }
}
