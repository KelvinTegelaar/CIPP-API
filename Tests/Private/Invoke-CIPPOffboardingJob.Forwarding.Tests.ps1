# Pester tests for the offboarding "Forward email" step, end to end.
#
# The wizard's forward field is an autocomplete ({ label, value = Entra object id }). It travels:
# request body -> scheduled task JSON -> Push-ExecScheduledCommand (-AsHashtable) -> Invoke-CIPPOffboardingJob
# -> orchestrator batch JSON -> Push-CIPPOffboardingTask -> real Set-CIPPForwarding -> Set-Mailbox.
# Every case asserts what reaches Exchange: Identity is the leaver, ForwardingAddress is the chosen
# recipient and never the leaver.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $JobPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Invoke-CIPPOffboardingJob.ps1'
    $HtmlPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPHtmlIsEmpty.ps1'
    $TaskPath = Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/Push-CIPPOffboardingTask.ps1'
    $ForwardingPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPForwarding.ps1'

    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $headers, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Write-Information { param($MessageData) }
    function New-CIPPAsyncDeployment { param($JobId, $Names, $StepTitles, $Source, $TaskId, $TenantFilter) }
    function Set-CIPPAsyncDeploymentStatus { param($JobId, $Name, $Status, $Logs) }
    function Set-CIPPAsyncDeploymentStep { param($JobId, $Name, $StepIndex, $StepStatus, $Message) }

    . $HtmlPath
    . $JobPath
    . $TaskPath

    # Push-CIPPOffboardingTask only runs cmdlets exported by CIPPCore, so the real Set-CIPPForwarding is
    # loaded into a module of that name next to a New-ExoRequest that records each call.
    $null = New-Module -Name CIPPCore -ArgumentList $ForwardingPath -ScriptBlock {
        param($ForwardingPath)
        . $ForwardingPath
        function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Anchor) $global:CippExoCalls.Add([pscustomobject]@{ Cmdlet = $cmdlet; Params = $cmdParams; Anchor = $Anchor }) }
        function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant, $LogData) }
        function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
        function Set-CIPPMailboxType { param($userid, $username, $tenantFilter, $MailboxType, $APIName, $Headers) "Converted $username to $MailboxType" }
        function Remove-CIPPMailboxRule { param($userid, $username, $tenantFilter, $APIName, $RemoveAllRules, $Headers) 'Removed rules' }
        function Set-CIPPSignInState { param($TenantFilter, $userid, $AccountEnabled, $APIName, $Headers) 'Disabled sign-in' }
        function Set-CIPPHideFromGAL { param($tenantFilter, $UserID, $hidefromgal, $APIName, $Headers) 'Hidden' }
        function Set-CIPPOutOfOffice { param($tenantFilter, $UserID, $InternalMessage, $ExternalMessage, $APIName, $state, $Headers) 'OOO set' }
        Export-ModuleMember -Function *
    } | Import-Module -Force -PassThru

    $script:Users = @{
        'leaver@contoso.com' = [pscustomobject]@{ id = 'leaver-id'; displayName = 'Lee Ver' }
        'second@contoso.com' = [pscustomobject]@{ id = 'second-id'; displayName = 'Sec Ond' }
    }

    # The wizard's options as posted: the request body minus user, tenantFilter and Scheduled
    function New-WizardOptions {
        param([hashtable]$Extra = @{})
        $Body = [pscustomobject]@{
            tenantFilter = 'contoso.com'
            user         = @([pscustomobject]@{ label = 'Lee Ver (leaver@contoso.com)'; value = 'leaver@contoso.com' })
            Scheduled    = [pscustomobject]@{ enabled = $false }
            forward      = [pscustomobject]@{ label = 'Manager Person (manager@contoso.com)'; value = 'manager-id' }
            KeepCopy     = $true
        }
        foreach ($Key in $Extra.Keys) { $Body | Add-Member -NotePropertyName $Key -NotePropertyValue $Extra[$Key] -Force }
        $Body | Select-Object * -ExcludeProperty user, tenantFilter, Scheduled
    }

    # Runs one user's offboarding the way the scheduler and orchestrator do, including every JSON hop
    function Invoke-OffboardingPipeline {
        param($Options, [string]$Username, [int[]]$StepIndexes = @())
        $Stored = @{ Username = $Username; APIName = 'Scheduled Offboarding'; options = $Options; RunScheduled = $true; DeploymentId = 'job-1' }
        if ($StepIndexes.Count -gt 0) { $Stored.StepIndexes = $StepIndexes }
        $StoredJson = $Stored | ConvertTo-Json -Depth 10 -Compress
        $CommandParameters = $StoredJson | ConvertFrom-Json | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable

        $null = Invoke-CIPPOffboardingJob -TenantFilter 'contoso.com' @CommandParameters

        foreach ($Item in $script:CapturedInput.Batch) {
            $QueuedItem = $Item | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $null = Push-CIPPOffboardingTask -Item $QueuedItem
        }
        $StoredJson
    }
}

AfterAll {
    Remove-Module -Name CIPPCore -Force -ErrorAction SilentlyContinue
    Remove-Variable -Name CippExoCalls -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Offboarding forward email' {
    BeforeEach {
        $global:CippExoCalls = [System.Collections.Generic.List[object]]::new()
        $script:CapturedInput = $null
        Mock -CommandName New-GraphGetRequest -MockWith {
            $Upn = ($uri -split '/users/')[1] -split '\?' | Select-Object -First 1
            $script:Users[$Upn]
        }
        Mock -CommandName Start-CIPPOrchestrator -MockWith { $script:CapturedInput = $InputObject; 'orch-1' }
    }

    It 'forwards the leaver''s mailbox to the chosen recipient' {
        $null = Invoke-OffboardingPipeline -Options (New-WizardOptions) -Username 'leaver@contoso.com'

        $Calls = @($global:CippExoCalls | Where-Object { $_.Cmdlet -eq 'Set-Mailbox' })
        $Calls.Count | Should -Be 1
        $Calls[0].Params.Identity | Should -Be 'leaver-id'
        $Calls[0].Params.ForwardingAddress | Should -Be 'manager-id'
        $Calls[0].Params.DeliverToMailboxAndForward | Should -BeTrue
        $Calls[0].Anchor | Should -Be 'leaver@contoso.com'
    }

    It 'still forwards to the recipient alongside the usual wizard actions' {
        $Options = New-WizardOptions -Extra @{
            ConvertToShared = $true; RemoveRules = $true; DisableSignIn = $true; HideFromGAL = $true
            OOO             = '<p>Gone</p>'; disableForwarding = $false
        }
        $null = Invoke-OffboardingPipeline -Options $Options -Username 'leaver@contoso.com'

        $Forwards = @($global:CippExoCalls | Where-Object { $_.Params.ForwardingAddress })
        $Forwards.Count | Should -Be 1
        $Forwards[0].Params.ForwardingAddress | Should -Be 'manager-id'
        @($global:CippExoCalls | Where-Object { $_.Params.ForwardingAddress -in 'leaver-id', 'leaver@contoso.com' }) | Should -BeNullOrEmpty
    }

    It 'gives every user in one wizard run the same recipient, never themselves' {
        $Options = New-WizardOptions
        foreach ($Upn in 'leaver@contoso.com', 'second@contoso.com') {
            $null = Invoke-OffboardingPipeline -Options $Options -Username $Upn
        }

        $Calls = @($global:CippExoCalls | Where-Object { $_.Cmdlet -eq 'Set-Mailbox' })
        $Calls.Count | Should -Be 2
        $Calls.Params.Identity | Should -Be @('leaver-id', 'second-id')
        $Calls.Params.ForwardingAddress | Should -Be @('manager-id', 'manager-id')
    }

    It 'sends the same Set-Mailbox when the forward step is re-run from the stored task' {
        $StoredJson = Invoke-OffboardingPipeline -Options (New-WizardOptions) -Username 'leaver@contoso.com'
        $First = $global:CippExoCalls[0]
        $ForwardIndex = [array]::IndexOf(@($script:CapturedInput.Batch.Cmdlet), 'Set-CIPPForwarding')
        $global:CippExoCalls.Clear()

        $Stored = $StoredJson | ConvertFrom-Json
        $null = Invoke-OffboardingPipeline -Options $Stored.options -Username $Stored.Username -StepIndexes @($ForwardIndex)

        $global:CippExoCalls.Count | Should -Be 1
        ($global:CippExoCalls[0].Params | ConvertTo-Json -Compress) | Should -Be ($First.Params | ConvertTo-Json -Compress)
    }

    It 'forwards to a bare-string address from an API caller' {
        $Options = New-WizardOptions -Extra @{ forward = 'manager@contoso.com' }
        $null = Invoke-OffboardingPipeline -Options $Options -Username 'leaver@contoso.com'

        @($global:CippExoCalls | Where-Object { $_.Params.ForwardingAddress -eq 'manager@contoso.com' }).Count | Should -Be 1
    }
}
