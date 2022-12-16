#requires -Version 7.2

[CmdletBinding(DefaultParameterSetName = 'interactive')]
Param(
    [Parameter(Mandatory = $true, ParameterSetName = 'noninteractive')]
    [ValidateSet('readonly', 'editor', 'admin')]
    $Role,
    [Parameter(Mandatory = $true, ParameterSetName = 'noninteractive')]
    $SelectedUsers,
    [Parameter(ParameterSetName = 'noninteractive')]
    [Parameter(ParameterSetName = 'interactive')]
    $ExpirationHours = 1
)

$ResourceGroup = '##RESOURCEGROUP##'
$Subscription = '##SUBSCRIPTION##'

if (!(Get-Module -ListAvailable Microsoft.PowerShell.ConsoleGuiTools)) {
    Install-Module Microsoft.PowerShell.ConsoleGuiTools -Force
}

$Context = Get-AzContext
if (!$Context) {
    Write-Host "`n- Connecting to Azure"
    $Context = Connect-AzAccount -Subscription $Subscription
}
Write-Host "Connected to $($Context.Account)"

$swa = Get-AzStaticWebApp -ResourceGroupName $ResourceGroup
$Domain = $swa.CustomDomain | Select-Object -First 1

Write-Host "CIPP SWA - $($swa.name)"

if (!$Role) {
    $Role = @('readonly', 'editor', 'admin') | Out-ConsoleGridView -OutputMode Single -Title 'Select CIPP Role'
}

$CurrentUsers = Get-AzStaticWebAppUser -Name $swa.name -ResourceGroupName $ResourceGroup -AuthProvider all | Select-Object DisplayName, Role

$AllUsers = Get-AzADUser -Filter "UserType eq 'Member'" | Select-Object DisplayName, UserPrincipalName 

$SelectedUsers = $AllUsers | Where-Object { $CurrentUsers.DisplayName -notcontains $_.UserPrincipalName } | Out-ConsoleGridView -Title "Select users for role '$Role'"
Write-Host "Selected users: $($SelectedUsers.UserPrincipalName -join ', ')"

Write-Host 'Generating invite links...'
$InviteList = foreach ($User in $SelectedUsers) {
    $UserInvite = @{
        InputObject          = $swa
        Domain               = $Domain
        Provider             = 'aad'
        UserDetail           = $User.UserPrincipalName
        Role                 = $Role
        NumHoursToExpiration = $ExpirationHours
    }
    $Invite = New-AzStaticWebAppUserRoleInvitationLink @UserInvite

    [PSCustomObject]@{
        User    = $User.UserPrincipalName
        Role    = $Role
        Link    = $Invite.InvitationUrl
        Expires = $Invite.ExpiresOn
    }
}
$InviteList
$InviteList | Export-Csv -Path '.\cipp-invites.csv' -Append
Write-Host 'Invitations exported to .\cipp-invites.csv'
