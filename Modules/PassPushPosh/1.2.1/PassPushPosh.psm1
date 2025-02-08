#Region '.\Classes\PasswordPush.ps1' -1

class PasswordPush {
    [string]$Note
    [string]$Payload
    [string] hidden $__UrlToken
    [string] hidden $__LinkBase
    [bool]$RetrievalStep
    [bool]$IsExpired
    [bool]$IsDeleted
    [bool]$IsDeletableByViewer
    [int]$ExpireAfterDays
    [int]$DaysRemaining
    [int]$ExpireAfterViews
    [int]$ViewsRemaining
    [DateTime]$DateCreated
    [DateTime]$DateUpdated
    [DateTime]$DateExpired
    # Added by constructors:
    #[string]$URLToken
    #[string]$Link
    #[string]$LinkDirect
    #[string]$LinkRetrievalStep

    PasswordPush() {
        # Blank constructor
    }

    # Constructor to allow casting or explicit import from a PSObject Representing the result of an API call
    PasswordPush([PSCustomObject]$APIresponseObject) {
        throw NotImplementedException
    }

    # Allow casting or explicit import from the raw Content of an API call
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Scope = 'Function', Justification = 'Global variables are used for module session helpers.')]
    PasswordPush([string]$JsonResponse) {
        Write-Debug 'New PasswordPush object instantiated from JsonResponse string'
        Initialize-PassPushPosh # Initialize the module if not yet done.

        $_j = $JsonResponse | ConvertFrom-Json
        $this.Note = $_j.note
        $this.Payload = $_j.payload
        $this.IsExpired = $_j.expired
        $this.IsDeleted = $_j.deleted
        $this.IsDeletableByViewer = $_j.deletable_by_viewer
        $this.ExpireAfterDays = $_j.expire_after_days
        $this.DaysRemaining = $_j.days_remaining
        $this.ExpireAfterViews = $_j.expire_after_views
        $this.ViewsRemaining = $_j.views_remaining
        $this.DateCreated = $_j.created_at
        $this.DateUpdated = $_j.updated_at
        $this.DateExpired = if ($_j.expired_on) { $_j.expired_on } else { [DateTime]0 }
        $this.RetrievalStep = $_j.retrieval_step


        $this | Add-Member -Name 'UrlToken' -MemberType ScriptProperty -Value {
            return $this.__UrlToken
        } -SecondValue {
            $this.__UrlToken = $_
            $this.__LinkBase = $_j.html_url ?? "$Script:PPPBaseUrl/p/$($this.__UrlToken)"
        }
        $this.__UrlToken = $_j.url_token
        $this.__LinkBase = $_j.html_url ?? "$Script:PPPBaseUrl/p/$($this.__UrlToken)"
        $this | Add-Member -Name 'LinkDirect' -MemberType ScriptProperty -Value { return $this.__LinkBase } -SecondValue {
            Write-Warning 'LinkDirect is a read-only calculated member.'
            Write-Debug 'Link* members are calculated based on the Global BaseUrl and Push Retrieval Step values'
        }
        $this | Add-Member -Name 'LinkRetrievalStep' -MemberType ScriptProperty -Value { return "$($this.__LinkBase)/r" } -SecondValue {
            Write-Warning 'LinkRetrievalStep is a read-only calculated member.'
            Write-Debug 'Link* members are calculated based on the Global BaseUrl and Push Retrieval Step values'
        }
        $this | Add-Member -Name 'Link' -MemberType ScriptProperty -Value {
            $_Link = if ($this.RetrievalStep) { $this.LinkRetrievalStep } else { $this.LinkDirect }
            Write-Debug "Presented Link: $_link"
            $_Link
        } -SecondValue {
            Write-Warning 'Link is a read-only calculated member.'
            Write-Debug 'Link* members are calculated based on the Global BaseUrl and Push Retrieval Step values'
        }
    }
}
#EndRegion '.\Classes\PasswordPush.ps1' 80
#Region '.\Classes\TypeAccelerators.ps1' -1

# https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_classes?view=powershell-7.4#exporting-classes-with-type-accelerators
# Define the types to export with type accelerators.
$ExportableTypes =@(
    [PasswordPush]
)
# Get the internal TypeAccelerators class to use its static methods.
$TypeAcceleratorsClass = [psobject].Assembly.GetType(
    'System.Management.Automation.TypeAccelerators'
)
# Ensure none of the types would clobber an existing type accelerator.
# If a type accelerator with the same name exists, throw an exception.
$ExistingTypeAccelerators = $TypeAcceleratorsClass::Get
foreach ($Type in $ExportableTypes) {
    if ($Type.FullName -in $ExistingTypeAccelerators.Keys) {
        $Message = @(
            "Unable to register type accelerator '$($Type.FullName)'"
            'Accelerator already exists.'
        ) -join ' - '

        throw [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new($Message),
            'TypeAcceleratorAlreadyExists',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $Type.FullName
        )
    }
}
# Add type accelerators for every exportable type.
foreach ($Type in $ExportableTypes) {
    $TypeAcceleratorsClass::Add($Type.FullName, $Type)
}
# Remove type accelerators when the module is removed.
($MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    foreach($Type in $ExportableTypes) {
        $TypeAcceleratorsClass::Remove($Type.FullName)
    }
}.GetNewClosure()) | Out-Null
#EndRegion '.\Classes\TypeAccelerators.ps1' 38
#Region '.\Private\ConvertTo-PasswordPush.ps1' -1

    <#
    .SYNOPSIS
    Convert API call response to a PasswordPush object

    .DESCRIPTION
    Accepts a JSON string returned from the Password Pusher API and converts it to a [PasswordPush] object.
    This allows calculated push retrieval URLs and a more "PowerShell" experience.
    Generally you won't need to use this directly, it's automatically invoked within Register-Push and Request-Push.

    .PARAMETER JsonResponse
    The string result of an API call from the Password Pusher application

    .INPUTS
    [string]

    .OUTPUTS
    [PasswordPush] for single object
    [PasswordPush[]] for Json array data

    .EXAMPLE
    # Common usage - from within the Register-Push cmdlet
    PS> $myPush = Register-Push -Payload "This is my secret!"
    PS> $myPush.Link  # The link parameter always presents the URL as it would appear with the same settings selected on pwpush.com

    https://pwpush.com/p/rz6nryvl-d4

    .EXAMPLE
    # Manually invoking the API
    PS> $rawJson = Invoke-WebRequest  `
                    -Uri https://pwpush.com/p.json `
                    -Method Post `
                    -Body '{"password": { "payload": "This is my secret!"}}' `
                    -ContentType 'application/json' |
                    Select-Object -ExpandProperty Content
    PS> $rawJson
    {"expire_after_days":7,"expire_after_views":5,"expired":false,"url_token":"rz6nryvl-d4","created_at":"2022-11-18T14:16:29.821Z","updated_at":"2022-11-18T14:16:29.821Z","deleted":false,"deletable_by_viewer":true,"retrieval_step":false,"expired_on":null,"days_remaining":7,"views_remaining":5}
    PS> $rawJson | ConvertTo-PasswordPush
    UrlToken            : rz6nryvl-d4
    LinkDirect          : https://pwpush.com/p/rz6nryvl-d4
    LinkRetrievalStep   : https://pwpush.com/p/rz6nryvl-d4/r
    Link                : https://pwpush.com/p/rz6nryvl-d4
    Payload             :
    RetrievalStep       : False
    IsExpired           : False
    IsDeleted           : False
    IsDeletableByViewer : True
    ExpireAfterDays     : 7
    DaysRemaining       : 7
    ExpireAfterViews    : 5
    ViewsRemaining      : 5
    DateCreated         : 11/18/2022 2:16:29 PM
    DateUpdated         : 11/18/2022 2:16:29 PM
    DateExpired         : 1/1/0001 12:00:00 AM

    .LINK
    https://github.com/adamburley/PassPushPosh/blob/main/Docs/ConvertTo-PasswordPush.md

    .NOTES
    Needs a rewrite / cleanup
    #>
function ConvertTo-PasswordPush {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Scope = 'Function', Justification = 'Creates a new object, no risk of overwriting data.')]
    [CmdletBinding()]
    [OutputType([PasswordPush])]
    param(
        [parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        $JsonResponse
    )
    process {
        try {
            $jsonObject = if ($JsonResponse -is [string]) { $JsonResponse | ConvertFrom-Json } else { $JsonResponse }
            foreach ($o in $jsonObject) {
                [PasswordPush]($o | ConvertTo-Json) # TODO fix this mess
            }
        }
        catch {
            Write-Debug 'Error in ConvertTo-PasswordPush coercing JSON object to PasswordPush object'
            Write-Debug "JsonResponse parameter value: [[$JsonResponse]]"
            Write-Error $_
        }
    }
}
#EndRegion '.\Private\ConvertTo-PasswordPush.ps1' 84
#Region '.\Private\Format-PasswordPusherSecret.ps1' -1

function Format-PasswordPusherSecret {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Secret,

        [Parameter()]
        [switch]$ShowSample
    )
    process {
        if ($Secret -eq '') {
            "length 0"
            continue
        }
        $length = $Secret.Length
        $last4 = $Secret.Substring($length - 4)
        if ($ShowSample) {
            "length $length ending [$last4]"
        }
        else {
            "length $length"
        }
    }
}
#EndRegion '.\Private\Format-PasswordPusherSecret.ps1' 27
#Region '.\Private\Invoke-PasswordPusherAPI.ps1' -1

function Invoke-PasswordPusherAPI {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [string]$Endpoint,
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method = [Microsoft.PowerShell.Commands.WebRequestMethod]::Get,
        [object]$Body,

        [Switch]$ReturnErrors
    )
    process {
        $_uri = "$Script:PPPBaseURL/$Endpoint"
        Write-Debug "Invoke-PasswordPusherAPI: $Method $_uri"

        $iwrSplat = @{
            'Method'      = $Method
            'ContentType' = 'application/json'
            'Body'        = ($body | ConvertTo-Json)
            'Uri'         = $_uri
            'UserAgent'   = $Script:PPPUserAgent
        }
        if ($Script:PPPHeaders.'X-User-Token') {
            $iwrSplat['Headers'] = $Script:PPPHeaders
            Write-Debug "Authenticated with API token $(Format-PasswordPusherSecret -Secret $Script:PPPHeaders.'X-User-Token' -ShowSample)"
        }
        if ($Script:PPPHeaders.'Authorization') {
            $iwrSplat['Headers'] = $Script:PPPHeaders
            Write-Debug "Authenticated with API token $(Format-PasswordPusherSecret -Secret $Script:PPPHeaders.'Authorization' -ShowSample)"
        }
        $callInfo = "$Method $_uri"
        Write-Verbose "Sending HTTP request: $callInfo"

        $call = Invoke-WebRequest @iwrSplat -SkipHttpErrorCheck
        Write-Debug "Response: $($call.StatusCode) $($call.Content)"
        if (Test-Json -Json $call.Content) {
            $result = $call.Content | ConvertFrom-Json
            if ($ReturnErrors -or $call.StatusCode -eq 200 -or $null -eq $result.error) {
                $result
            } else {
                Write-Error -Message "$callInfo : $($call.StatusCode) $($result.error)"
            }
        } else {
            Write-Error -Message "Parseable JSON not returned by API. $callInfo : $($call.StatusCode) $($call.Content)"
        }
    }
}
#EndRegion '.\Private\Invoke-PasswordPusherAPI.ps1' 47
#Region '.\Public\Get-Dashboard.ps1' -1

<#
    .SYNOPSIS
    Get a list of active or expired Pushes for an authenticated user

    .DESCRIPTION
    Retrieves a list of Pushes - active or expired - for an authenticated user.
    Active and Expired are different endpoints, so to get both you'll need to make
    two calls.

    .PARAMETER Dashboard
    The type of dashboard to retrieve. Active or Expired.

    .INPUTS
    [string] 'Active' or 'Expired'

    .OUTPUTS
    [PasswordPush[]] Array of pushes with data

    .EXAMPLE
    Get-Dashboard

    .EXAMPLE
    Get-Dashboard Active

    .LINK
    https://github.com/adamburley/PassPushPosh/blob/main/Docs/Get-Dashboard.md

    .LINK
    https://pwpush.com/api/1.0/passwords/active.en.html

    .LINK
    Get-PushAuditLog

    #>
function Get-Dashboard {
    [CmdletBinding()]
    [OutputType([PasswordPush[]])]
    param(
        [parameter(Position = 0)]
        [ValidateSet('Active', 'Expired')]
        [ValidateNotNullOrEmpty()]
        [string]
        $Dashboard = 'Active'
    )
    process {
        if (-not $Script:PPPHeaders) { Write-Error 'Dashboard access requires authentication. Run Initialize-PassPushPosh and pass your email address and API key before retrying.' -ErrorAction Stop -Category AuthenticationError }
        $uri = "p/$($Dashboard -eq 'Active' ? 'active.json' : 'expired.json')"
        Invoke-PasswordPusherAPI -Endpoint $uri -Method Get | ConvertTo-PasswordPush
    }
}
#EndRegion '.\Public\Get-Dashboard.ps1' 51
#Region '.\Public\Get-Push.ps1' -1

<#
    .SYNOPSIS
    Retrieve the secret contents of a Push

    .DESCRIPTION
    Get-Push accepts a URL Token string and returns the contents of a Push along with
    metadata regarding that Push. Note: Get-Push will return data on an expired
    Push (datestamps, etc) even if it does not return the Push contents.

    .PARAMETER URLToken
    URL Token for the secret

    .PARAMETER Passhrase
    An additional phrase required to view the secret. Required if the Push was created with a Passphrase.

    .INPUTS
    [string]

    .OUTPUTS
    [PasswordPush]

    .EXAMPLE
    Get-Push -URLToken gzv65wiiuciy

    .EXAMPLE
    Get-Push -URLToken gzv65wiiuciy -Passphrase "My Passphrase"

    .LINK
    https://github.com/adamburley/PassPushPosh/blob/main/Docs/Get-Push.md

    .LINK
    https://pwpush.com/api/1.0/passwords.en.html

    .LINK
    https://github.com/pglombardo/PasswordPusher/blob/c2909b2d5f1315f9b66939c9fbc7fd47b0cfeb03/app/controllers/passwords_controller.rb#L89

    .LINK
    New-Push

    #>
function Get-Push {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "Passphrase", Justification = "DE0001: SecureString shouldn't be used")]
    [CmdletBinding()]
    [OutputType([PasswordPush])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [Alias('Token')]
        $URLToken,

        [Parameter()]
        [String]$Passphrase
    )
    begin { Initialize-PassPushPosh -Verbose:$VerbosePreference -Debug:$DebugPreference }
    process {
        $endpoint = $Passphrase ? "p/$URLToken.json?passphrase=$Passphrase" : "p/$URLToken.json"
        $result = Invoke-PasswordPusherAPI -Endpoint $endpoint -ReturnErrors
        switch ($result.error){
            'not-found' { Write-Error -Message "Push not found. Check the token you provided. Tokens are case-sensitive." }
            'This push has a passphrase that was incorrect or not provided.' { if ($Passphrase) { Write-Error -Message "Incorrect passphrase provided." } else { Write-Error -Message "Passphrase required. Specify with the -Passphrase parameter." } }
            default { $result | ConvertTo-PasswordPush }
        }
    }
}
#EndRegion '.\Public\Get-Push.ps1' 65
#Region '.\Public\Get-PushAccount.ps1' -1

<#
    .SYNOPSIS
    Get a list of accounts for an authenticated user

    .DESCRIPTION
    Retrieves a list of accounts for an authenticated user.

    .LINK
    Get-PushAuditLog

    #>
function Get-PushAccount {
    [CmdletBinding()]
    [OutputType([PasswordPush[]])]
    param()
    process {
        if (-not $Script:PPPHeaders) { Write-Error 'Dashboard access requires authentication. Run Initialize-PassPushPosh and pass your email address and API key before retrying.' -ErrorAction Stop -Category AuthenticationError }
        $uri = 'api/v1/accounts'
        Invoke-PasswordPusherAPI -Endpoint $uri -Method Get
    }
}
#EndRegion '.\Public\Get-PushAccount.ps1' 22
#Region '.\Public\Get-PushAuditLog.ps1' -1

<#
    .SYNOPSIS
    Get the view log of an authenticated Push

    .DESCRIPTION
    Retrieves the view log of a Push created under an authenticated session.
    Returns an array of custom objects with view data. If the query is
    successful but there are no results, it returns an empty array.
    If there's an error, a single object is returned with information.
    See "handling errors" under NOTES

    .PARAMETER URLToken
    URL Token from a secret

    .INPUTS
    [string]

    .OUTPUTS
    [PsCustomObject[]] Array of entries.
    [PsCustomObject] If there's an error in the call, it will be returned an object with a property
    named 'error'.  The value of that member will contain more information

    .EXAMPLE
    Get-PushAuditLog -URLToken 'mytokenfromapush'
    ip         : 75.202.43.56,102.70.135.200
    user_agent : Mozilla/5.0 (Macintosh; Darwin 21.6.0 Darwin Kernel Version 21.6.0: Mon Aug 22 20:20:05 PDT 2022; root:xnu-8020.140.49~2/RELEASE_ARM64_T8101;
    en-US) PowerShell/7.2.7
    referrer   :
    successful : True
    created_at : 11/19/2022 6:32:42 PM
    updated_at : 11/19/2022 6:32:42 PM
    kind       : 0

    .EXAMPLE
    # If there are no views, an empty array is returned
    Get-PushAuditLog -URLToken 'mytokenthatsneverbeenseen'

    .LINK
    https://github.com/adamburley/PassPushPosh/blob/main/Docs/Get-PushAuditLog.md

    .LINK
    https://pwpush.com/api/1.0/passwords/audit.en.html

    .LINK
    Get-Dashboard

    .NOTES
    Handling Errors:
    The API returns different HTTP status codes and results depending where the
    call fails.

    |  HTTP RESPONSE   |            Error Reason         |                Response Body                 |                                    Sample Object Returned                                  |                                                             Note                                                           |
    |------------------|---------------------------------|----------------------------------------------|--------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------|
    | 401 UNAUTHORIZED | Invalid API key or email        | None                                         | @{ 'Error'= 'Authentication error. Verify email address and API key.'; 'ErrorCode'= 401 }  |                                                                                                                            |
    | 200 OK           | Push created by another account | {"error":"That push doesn't belong to you."} | @{ 'Error'= "That Push doesn't belong to you"; 'ErrorCode'= 403 }                          | Function transforms error code to 403 to allow easier response management                                                  |
    | 404 NOT FOUND    | Invalid URL token               | None                                         | @{ 'Error'= 'Invalid token. Verify your Push URL token is correct.'; 'ErrorCode'= 404 }    | This is different than the response to a delete Push query - in this case it will only return 404 if the token is invalid. |

    #>
function Get-PushAuditLog {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias('Token')]
        [string]
        $URLToken
    )
    begin {
        if (-not $Script:PPPHeaders) { Write-Error 'Retrieving audit logs requires authentication. Run Initialize-PassPushPosh and pass your email address and API key before retrying.' -ErrorAction Stop -Category AuthenticationError }
    }
    process {
        $response = Invoke-PasswordPusherAPI -Endpoint "p/$URLToken/audit.json" -ReturnErrors
        switch ($response.error) {
            'not-found' { Write-Error -Message "Push not found. Check the token you provided. Tokens are case-sensitive." }
            { $null -ne $_ -and $_ -ne 'not-found' } { Write-Error -Message $_ }
            default { $response | Select-Object -ExpandProperty views }
        }
    }
}
#EndRegion '.\Public\Get-PushAuditLog.ps1' 80
#Region '.\Public\Get-SecretLink.ps1' -1

<#
    .SYNOPSIS
    Returns a fully qualified secret link to a push of given URL Token

    .DESCRIPTION
    Accepts a string value for a URL Token and retrieves a full URL link to the secret.
    Returned value is a 1-step retrieval link depending on option selected during Push creation.
    Returns false if URL Token is invalid, however it will return a URL if the token is valid
    but the Push is expired or deleted.

    .PARAMETER URLToken
    URL Token for the secret

    .INPUTS
    [string] URL Token value

    .OUTPUTS
    [string] Fully qualified URL

    .EXAMPLE
    Get-SecretLink -URLToken gzv65wiiuciy
    https://pwpush.com/p/gzv65wiiuciy/r

    .EXAMPLE
    Get-SecretLink -URLToken gzv65wiiuciy -Raw
    { "url": "https://pwpush.com/p/0fkapnbo_pwp4gi8uy0/r" }

    .LINK
    https://github.com/adamburley/PassPushPosh/blob/main/Docs/Get-SecretLink.md

    .LINK
    https://pwpush.com/api/1.0/passwords/preview.en.html

    .NOTES
    Including this endpoint for completeness - however it is generally unnecessary.
    The only thing this endpoint does is return a different value depending if "Use 1-click retrieval step"
    was selected when the Push was created.  Since both the 1-click and the direct links are available
    regardless if that option is selected, the links are calculable and both are included by default in a
    [PasswordPush] object.

    As it returns false if a Push URL token is not valid you can use it to test if a Push exists without
    burning a view.
    #>
function Get-SecretLink {
    [CmdletBinding()]
    [Alias('Get-PushPreview')]
    [OutputType('[string]')]
    param(
        [parameter(Mandatory, ValueFromPipeline)]
        [Alias('Token')]
        [ValidateLength(5, 256)]
        [string]$URLToken
    )
    begin { Initialize-PassPushPosh -Verbose:$VerbosePreference -Debug:$DebugPreference }
    process {
        Invoke-PasswordPusherAPI -Endpoint "p/$URLToken/preview.json" | Select-Object -ExpandProperty url
    }
}
#EndRegion '.\Public\Get-SecretLink.ps1' 59
#Region '.\Public\Initialize-PassPushPosh.ps1' -1

<#
    .SYNOPSIS
    Initialize the PassPushPosh module

    .DESCRIPTION
    Initialize-PassPushPosh sets variables for the module's use during the remainder of the session.
    Server URL and User Agent values are set by default but may be overridden.
    If invoked with email address and API key, calls are sent as authenticated. Otherwise they default to
    anonymous.

    This function is called automatically if needed, defaulting to the public pwpush.com service.

    .PARAMETER AccountType
    For paid users, specify the account type as Premium or Pro. Not required for free accounts and self-hosted.

    .PARAMETER EmailAddress
    Email address for authenticated calls.

    .PARAMETER ApiKey
    API key for authenticated calls.

    .PARAMETER BaseUrl
    Base URL for API calls. Allows use of module with private instances of Password Pusher
    Default: https://pwpush.com

    .PARAMETER UserAgent
    Set a specific user agent. Default user agent is a combination of the
    module info, what your OS reports itself as, and a hash based on
    your username + workstation or domain name. This way the UA can be
    semi-consistent across sessions but not identifying.

    Note: User agent must meet [RFC9110](https://www.rfc-editor.org/rfc/rfc9110#name-user-agent) specifications or the Password Pusher API will reject the call.

    .PARAMETER Force
    Force setting new information. If module is already initialized you can use this to
    Re-initialize with default settings. Implied if either ApiKey or BaseUrl is provided.

    .EXAMPLE
    # Initialize with default settings
    PS > Initialize-PassPushPosh

    .EXAMPLE
    # Initialize with authentication
    PS > Initialize-PassPushPosh -EmailAddress 'youremail@example.com' -ApiKey '239jf0jsdflskdjf' -Verbose

    VERBOSE: Initializing PassPushPosh. ApiKey: [x-kdjf], BaseUrl: https://pwpush.com

    .EXAMPLE
    # Initialize with another server with authentication
    PS > Initialize-PassPushPosh -BaseUrl https://myprivatepwpushinstance.com -EmailAddress 'youremail@example.com' -ApiKey '239jf0jsdflskdjf' -Verbose

    VERBOSE: Initializing PassPushPosh. ApiKey: [x-kdjf], BaseUrl: https://myprivatepwpushinstance.com

    .EXAMPLE
    # Set a custom User Agent
    PS > InitializePassPushPosh -UserAgent "My-CoolUserAgent/1.12.1"

    .LINK
    https://github.com/adamburley/PassPushPosh/blob/main/Docs/Initialize-PassPushPosh.md

    .NOTES
    -WhatIf setting for Set-Variable -Script is disabled, otherwise -WhatIf
    calls for other functions would return incorrect data in the case this
    function has not yet run.
    #>
function Initialize-PassPushPosh {
    [CmdletBinding(DefaultParameterSetName = 'Anonymous')]
    param (
        [Parameter(ParameterSetName = 'Pro')]
        [ValidateSet('Premium', 'Pro')]
        [string]$AccountType = 'Pro',

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Authenticated')]
        [ValidatePattern('.+\@.+\..+', ErrorMessage = 'Please specify a valid email address')]
        [string]$EmailAddress,

        [Parameter(Mandatory, ParameterSetName = 'Pro')]
        [Parameter(Mandatory, Position = 1, ParameterSetName = 'Authenticated')]
        [ValidateLength(5, 256)]
        [string]$ApiKey,

        [Parameter(Position = 0, ParameterSetName = 'Anonymous')]
        [Parameter(Position = 2, ParameterSetName = 'Authenticated')]
        [Parameter(ParameterSetName = 'Pro')]
        [ValidatePattern('^https?:\/\/[a-zA-Z0-9-_]+.[a-zA-Z0-9]+')]
        [string]$BaseUrl,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $UserAgent,

        [Parameter()][switch]$Force
    )
    if ($Script:PPPBaseURL -and $true -inotin $Force, [bool]$ApiKey, [bool]$BaseUrl, [bool]$UserAgent) { Write-Debug -Message 'PassPushPosh is already initialized.' }
    else {
        $defaultBaseUrl = 'https://pwpush.com'
        $apiKeyOutput = $ApiKey ? (Format-PasswordPusherSecret -Secret $ApiKey -ShowSample) : 'None'

        if (-not $Script:PPPBaseURL) {
            # Not initialized
            if (-not $BaseUrl) { $BaseUrl = $defaultBaseUrl }
            Write-Verbose "Initializing PassPushPosh. ApiKey: [$apiKeyOutput], BaseUrl: $BaseUrl"
        }
        elseif ($Force -or $ApiKey -or $BaseURL) {
            if (-not $BaseUrl) { $BaseUrl = $defaultBaseUrl }
            $oldApiKeyOutput = if ($Script:PPPApiKey) { Format-PasswordPusherSecret -Secret $Script:PPPApiKey -ShowSample } else { 'None' }
            Write-Verbose "Re-initializing PassPushPosh. Old ApiKey: [$oldApiKeyOutput] New ApiKey: [$apiKeyOutput], Old BaseUrl: $Script:PPPBaseUrl New BaseUrl: $BaseUrl"
        }
        if ($PSCmdlet.ParameterSetName -eq 'Authenticated') {

            Set-Variable -Scope Script -Name PPPHeaders -WhatIf:$false -Value @{
                'X-User-Email' = $EmailAddress
                'X-User-Token' = $ApiKey
            }
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'Pro') {
            Write-Debug "Initializing for paid tier $($AccountType)"
            Set-Variable -Scope Script -Name PPPHeaders -WhatIf:$false -Value @{
                'Authorization' = "Bearer $ApiKey"
            }
        }
        elseif ($Script:PPPHeaders) {
            # Remove if present - covers case where module is reinitialized from an authenticated to an anonymous session
            Remove-Variable -Scope Script -Name PPPHeaders -WhatIf:$false
        }

        if (-not $UserAgent) {
            $osVersion = [System.Environment]::OSVersion
            $userAtDomain = '{0}@{1}' -f [System.Environment]::UserName, [System.Environment]::UserDomainName
            $uAD64 = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($userAtDomain))
            Write-Debug "$userAtDomain transformed to $uAD64. First 20 characters $($uAD64.Substring(0,20))"
            # Version tag is replaced by the semantic version number at build time. See PassPushPosh/issues/11 for context
            $UserAgent = "PassPushPosh/1.2.1 $osVersion/$($uAD64.Substring(0,20))"
            # $UserAgent = "PassPushPosh/$((Get-Module -Name PassPushPosh).Version.ToString()) $osVersion/$($uAD64.Substring(0,20))"
            Write-Verbose "Generated user agent: $UserAgent"
        }
        else {
            Write-Verbose "Using specified user agent: $UserAgent"
        }

        Set-Variable -WhatIf:$false -Scope Script -Name PPPBaseURL -Value $BaseUrl.TrimEnd('/')
        Set-Variable -WhatIf:$false -Scope Script -Name PPPUserAgent -Value $UserAgent
    }
}
#EndRegion '.\Public\Initialize-PassPushPosh.ps1' 146
#Region '.\Public\New-Push.ps1' -1

<#
    .SYNOPSIS
    Create a new Push

    .DESCRIPTION
    Create a new Push on the specified Password Pusher instance. The
    programmatic equivalent of going to pwpush.com and entering info.
    Returns [PasswordPush] object. Link member is a link created based on
    1-step setting however both 1-step and direct links
    are always provided at LinkRetrievalStep and LinkDirect properties.

    .PARAMETER Payload
    The URL password or secret text to share.

    .PARAMETER Passphrase
    Require recipients to enter this passphrase to view the created push.

    .PARAMETER Note
    The note for this push.  Visible only to the push creator. Requires authentication.

    .PARAMETER ExpireAfterDays
    Expire secret link and delete after this many days.

    .PARAMETER ExpireAfterViews
    Expire secret link and delete after this many views.

    .PARAMETER DeletableByViewer
    Allow the recipient of a Push to delete it.

    .PARAMETER RetrievalStep
    Require recipient click an extra link to view Push payload.
    Helps to avoid chat systems and URL scanners from eating up views.
    Note that the retrieval step URL is always available for a push. This
    parameter changes if the 1-click link is used in the Link parameter
    and returned from the secret link helper (Get-SecretLink)

    .PARAMETER AccountId
    Account ID to associate with this push. Requires authentication.

    .INPUTS
    [string]

    .OUTPUTS
    [PasswordPush] Representation of the submitted push

    .EXAMPLE
    $myPush = New-Push "Here's my secret!"
    PS > $myPush | Select-Object Link, LinkRetrievalStep, LinkDirect

    Link              : https://pwpush.com/p/gzv65wiiuciy   # Requested style
    LinkRetrievalStep : https://pwpush.com/p/gzv65wiiuciy/r # 1-step
    LinkDirect        : https://pwpush.com/p/gzv65wiiuciy   # Direct

    .EXAMPLE
    "Super secret secret" | New-Push -RetrievalStep | Select-Object -ExpandProperty Link

    https://pwpush.com/p/gzv65wiiuciy/r


    .EXAMPLE
    # "Burn after reading" style Push
    PS > New-Push -Payload "Still secret text!" -ExpireAfterViews 1 -RetrievalStep

    .LINK
    https://github.com/adamburley/PassPushPosh/blob/main/Docs/New-Push.md

    .LINK
    https://pwpush.com/api/1.0/passwords/create.en.html

    .LINK
    https://github.com/pglombardo/PasswordPusher/blob/c2909b2d5f1315f9b66939c9fbc7fd47b0cfeb03/app/controllers/passwords_controller.rb#L120

    .LINK
    Get-Push

    .NOTES
    Maximum for -ExpireAfterDays and -ExpireAfterViews is based on the default
    values for Password Pusher and what's used on the public instance
    (pwpush.com). If you're using this with a private instance and want to
    override that value you'll need to fork this module.
    #>
function New-Push {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'Passphrase', Justification = "DE0001: SecureString shouldn't be used")]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low', DefaultParameterSetName = 'Anonymous')]
    [OutputType([PasswordPush])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline, Position = 0)]
        [Alias('Password')]
        [ValidateNotNullOrEmpty()]
        [string]$Payload,

        [Parameter()]
        [string]$Passphrase,

        [Parameter(ParameterSetName = 'Authenticated')]
        [ValidateScript({ $null -ne $Script:PPPHeaders.'X-User-Token' -or $null -ne $Script:PPPHeaders.Authorization }, ErrorMessage = 'Adding a note requires authentication.')]
        [ValidateNotNullOrEmpty()]
        [string]$Note,

        [Parameter()]
        [ValidateRange(1, 90)]
        [int]
        $ExpireAfterDays,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]
        $ExpireAfterViews,

        [Parameter()]
        [switch]
        $DeletableByViewer,

        [Parameter()]
        [switch]
        $RetrievalStep,

        [Parameter()]
        [ValidateScript({ $null -ne $Script:PPPHeaders.Authorization }, ErrorMessage = 'Adding an account id requires authentication.')]
        $AccountId
    )

    begin {
        Initialize-PassPushPosh -Verbose:$VerbosePreference -Debug:$DebugPreference
    }
    process {
        $body = @{
            'password' = @{
                'payload' = $Payload
            }
        }
        $shouldString = 'Submit {0} push with Payload of length {1}' -f $PSCmdlet.ParameterSetName, $Payload.Length
        if ($Passphrase) {
            $body.password.passphrase = $Passphrase
            $shouldString += ", with passphrase of length $($Passphrase.Length)"
        }
        if ($Note) {
            $body.password.note = $note
            $shouldString += ", with note $note"
        }
        if ($ExpireAfterDays) {
            $body.password.expire_after_days = $ExpireAfterDays
            $shouldString += ', expire after {0} days' -f $ExpireAfterDays
        }
        if ($ExpireAfterViews) {
            $body.password.expire_after_views = $ExpireAfterViews
            $shouldString += ', expire after {0} views' -f $ExpireAfterViews
        }
        if ($AccountId) {
            $body.account_id = $AccountId
            $shouldString += ', with account ID {0}' -f $AccountId
        }
        $body.password.deletable_by_viewer = if ($DeletableByViewer) {
            $shouldString += ', deletable by viewer'
            $true
        } else {
            $shouldString += ', NOT deletable by viewer'
            $false
        }
        $body.password.retrieval_step = if ($RetrievalStep) {
            $shouldString += ', with a 1-click retrieval step'
            $true
        } else {
            $shouldString += ', with a direct link'
            $false
        }
        if ($PSCmdlet.ShouldProcess($shouldString, $iwrSplat.Uri, 'Submit new Push')) {
            $response = Invoke-PasswordPusherAPI -Endpoint 'p.json' -Method Post -Body $body
            $response | ConvertTo-PasswordPush
        }
    }
}
#EndRegion '.\Public\New-Push.ps1' 173
#Region '.\Public\Remove-Push.ps1' -1

<#
.SYNOPSIS
Remove a Push

.DESCRIPTION
Remove (invalidate) an active push. Requires the Push be either set as
deletable by viewer, or that you are authenticated as the creator of the
Push.

If you have authorization to delete a push (deletable by viewer TRUE or
you are the Push owner) the endpoint will always return 200 OK with a Push
object, regardless if the Push was previously deleted or expired.

If the Push URL Token is invalid OR you are not authorized to delete the
Push, the endpoint returns 404 and this function returns $false

.PARAMETER URLToken
URL Token for the secret

.PARAMETER PushObject
PasswordPush object

.INPUTS
[string] URL Token
[PasswordPush] representing the Push to remove

.OUTPUTS
[bool] True on success, otherwise False

.EXAMPLE
Remove-Push -URLToken bwzehzem_xu-

.EXAMPLE
Remove-Push -URLToken

.LINK
https://github.com/adamburley/PassPushPosh/blob/main/Docs/Remove-Push.md

.LINK
https://pwpush.com/api/1.0/passwords/destroy.en.html

.NOTES
TODO testing and debugging
#>
function Remove-Push {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Token')]
    [OutputType([PasswordPush], [bool])]
    param(
        [parameter(ValueFromPipeline, ParameterSetName = 'Token')]
        [ValidateNotNullOrEmpty()]
        [Alias('Token')]
        [string]
        $URLToken,

        [Parameter(ValueFromPipeline, ParameterSetName = 'Object')]
        [PasswordPush]
        $PushObject
    )
    process {
        if ($PSCmdlet.ParameterSetName -eq 'Object') {
            Write-Debug -Message "Remove-Push was passed a PasswordPush object with URLToken: [$($PushObject.URLToken)]"
            if (-not $PushObject.IsDeletableByViewer -and -not $Script:PPPHeaders) {
                #Pre-qualify if this will succeed
                Write-Warning -Message 'Unable to remove Push. Push is not marked as deletable by viewer and you are not authenticated.'
                continue
            }
            if ($PushObject.IsDeletableByViewer) {
                Write-Verbose "Push is flagged as deletable by viewer, should be deletable."
            }
            else { Write-Verbose "In an authenticated API session. Push will be deletable if it was created by authenticated user." }
            $URLToken = $PushObject.URLToken
        }
        else {
            Write-Debug -Message "Remove-Push was passed a URLToken: [$URLToken]"
        }
        Write-Verbose -Message "Push with URL Token [$URLToken] will be deleted if 'Deletable by viewer' was enabled or you are the creator of the push and are authenticated."
        if ($PSCmdlet.ShouldProcess('Delete', "Push with token [$URLToken]")) {
            $result = Invoke-PasswordPusherAPI -Endpoint "p/$URLToken.json" -Method 'Delete' -ReturnErrors
            if ($result.error) {
                Write-Error -Message "Unable to remove Push with token [$URLToken]. Error: $($result.error)"
            }
            else {
                $result | ConvertTo-PasswordPush
            }
        }
    }
}
#EndRegion '.\Public\Remove-Push.ps1' 88
