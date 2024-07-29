class PasswordPush {
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


        $this | Add-Member -Name 'UrlToken' -MemberType ScriptProperty -Value {
                return $this.__UrlToken
            } -SecondValue {
                $this.__UrlToken = $_
                $this.__LinkBase = "$Global:PPPBaseUrl/p/$($this.__UrlToken)"
            }
        $this.__UrlToken = $_j.url_token
        $this.__LinkBase = "$Global:PPPBaseUrl/p/$($this.__UrlToken)"
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
                return $_Link
            } -SecondValue {
                Write-Warning 'Link is a read-only calculated member.'
                Write-Debug 'Link* members are calculated based on the Global BaseUrl and Push Retrieval Step values'
            }
    }
}

function ConvertTo-PasswordPush {
    <#
    .SYNOPSIS
    Convert API call response to a PasswordPush object

    .DESCRIPTION
    Accepts a JSON string returned from the Password Pusher API and converts it to a [PasswordPush] object.
    This allows calculated push retrieval URLs and a more "PowerShell" experience.
    Generally you won't need to use this directly, it's automatically invoked within Register-Push and Request-Push.

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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Scope = 'Function', Justification = 'Creates a new object, no risk of overwriting data.')]
    [CmdletBinding()]
    [OutputType([PasswordPush])]
    param(
        # The string result of an API call from the Password Pusher application
        [parameter(Mandatory, ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]$JsonResponse
    )
    process {
        try {
            $jsonObject = $JsonResponse | ConvertFrom-Json
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
function Get-Dashboard {
    <#
    .SYNOPSIS
    Get a list of active or expired Pushes for an authenticated user

    .DESCRIPTION
    Retrieves a list of Pushes - active or expired - for an authenticated user.
    Active and Expired are different endpoints, so to get both you'll need to make
    two calls.

    .INPUTS
    [string] 'Active' or 'Expired'

    .OUTPUTS
    [PasswordPush[]] Array of pushes with data
    [string] raw response body from API call

    .EXAMPLE
    Get-Dashboard

    .EXAMPLE
    Get-Dashboard Active

    .EXAMPLE
    Get-Dashboard -Dashboard Expired

    .EXAMPLE
    Get-Dashboard -Raw
    [{"expire_after_days":1,"expire_after_views":5,"expired":false,"url_token":"xm3q7czvtdpmyg","created_at":"2022-11-19T18:10:42.055Z","updated_at":"2022-11-19T18:10:42.055Z","deleted":false,"deletable_by_viewer":true,"retrieval_step":false,"expired_on":null,"note":null,"days_remaining":1,"views_remaining":3}]

    .LINK
    https://github.com/adamburley/PassPushPosh/blob/main/Docs/Get-Dashboard.md

    .LINK
    https://pwpush.com/api/1.0/dashboard.en.html

    .LINK
    Get-PushAuditLog

    .NOTES
    TODO update Invoke-Webrequest flow and error-handling to match other functions
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Scope = 'Function', Justification = 'Global variables are used for module session helpers.')]
    [CmdletBinding()]
    [OutputType([PasswordPush[]],[string])]
    param(
        # URL Token from a secret
        [parameter(Position=0)]
        [ValidateSet('Active','Expired')]
        [ValidateNotNullOrEmpty()]
        [string]
        $Dashboard = 'Active',

        # Return content of API call directly
        [Parameter()]
        [switch]
        $Raw
    )
    if (-not $Global:PPPHeaders) { Write-Error 'Dashboard access requires authentication. Run Initialize-PassPushPosh and pass your email address and API key before retrying.' -ErrorAction Stop -Category AuthenticationError }
    try {
        $uri = "$Global:PPPBaseUrl/d/"
        if ($Dashboard -eq 'Active') { $uri += 'active.json' }
        elseif ($Dashboard -eq 'Expired') { $uri += 'expired.json' }
        Write-Debug "Requesting $uri"
        $response = Invoke-WebRequest -Uri $uri -Method Get -Headers $Global:PPPHeaders -ErrorAction Stop
        if ($Raw) { return $response.Content }
        else {
            return $response.Content | ConvertTo-PasswordPush
        }
    } catch {
        Write-Verbose "An exception was caught: $($_.Exception.Message)"
        if ($DebugPreference -eq [System.Management.Automation.ActionPreference]::Continue) {
            Set-Variable -Scope Global -Name 'PPPLastError' -Value $_
            Write-Debug -Message 'Response object set to global variable $PPPLastError'
        }
        throw # Re-throw the error
    }
}
function Get-Push {
    <#
    .SYNOPSIS
    Retrieve the secret contents of a Push

    .DESCRIPTION
    Accepts a URL Token string, returns the contents of a Push along with
    metadata regarding that Push. Note, Get-Push will return data on an expired
    Push (datestamps, etc) even if it does not return the Push contents.

    .INPUTS
    [string]

    .OUTPUTS
    [PasswordPush] or [string]

    .EXAMPLE
    Get-Push -URLToken gzv65wiiuciy

    .EXAMPLE
    Get-Push -URLToken gzv65wiiuciy -Raw
    {"payload":"I am your payload!","expired":false,"deleted":false,"expired_on":"","expire_after_days":1,"expire_after_views":4,"url_token":"bwzehzem_xu-","created_at":"2022-11-21T13:20:08.635Z","updated_at":"2022-11-21T13:23:45.342Z","deletable_by_viewer":true,"retrieval_step":false,"days_remaining":1,"views_remaining":4}

    .LINK
    https://github.com/adamburley/PassPushPosh/blob/main/Docs/Get-Push.md

    .LINK
    https://pwpush.com/api/1.0/passwords/show.en.html

    .LINK
    New-Push

    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars','',Scope='Function',Justification='Global variables are used for module session helpers.')]
    [CmdletBinding()]
    [OutputType([PasswordPush])]
    param(
        # URL Token for the secret
        [parameter(Mandatory,ValueFromPipeline,Position=0)]
        [ValidateNotNullOrEmpty()]
        [Alias('Token')]
        $URLToken,

        # Return the raw response body from the API call
        [Parameter()]
        [switch]
        $Raw
    )
    begin { Initialize-PassPushPosh -Verbose:$VerbosePreference -Debug:$DebugPreference }

    process {
        try {
            $iwrSplat = @{
                'Method' = 'Get'
                'ContentType' = 'application/json'
                'Uri' = "$Global:PPPBaseUrl/p/$URLToken.json"
                'UserAgent' = $Global:PPPUserAgent
            }
            if ($Global:PPPHeaders) { $iwrSplat['Headers'] = $Global:PPPHeaders }
            Write-Verbose "Sending HTTP request: $($iwrSplat | Out-String)"
            $response = Invoke-WebRequest @iwrSplat -ErrorAction Stop
            if ($DebugPreference -eq [System.Management.Automation.ActionPreference]::Continue) {
                Set-Variable -Scope Global -Name PPPLastCall -Value $response
                Write-Debug 'Response to Invoke-WebRequest set to PPPLastCall Global variable'
            }
            if ($Raw) {
                Write-Debug "Returning raw object:`n$($response.Content)"
                return $response.Content
            }
            return $response.Content | ConvertTo-PasswordPush
        } catch {
            Write-Verbose "An exception was caught: $($_.Exception.Message)"
            if ($DebugPreference -eq [System.Management.Automation.ActionPreference]::Continue) {
                Set-Variable -Scope Global -Name PPPLastError -Value $_
                Write-Debug -Message 'Response object set to global variable $PPPLastError'
            }
        }
    }
}
function Get-PushAuditLog {
    <#
    .SYNOPSIS
    Get the view log of an authenticated Push

    .DESCRIPTION
    Retrieves the view log of a Push created under an authenticated session.
    Returns an array of custom objects with view data. If the query is
    successful but there are no results, it returns an empty array.
    If there's an error, a single object is returned with information.
    See "handling errors" under NOTES

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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Scope = 'Function', Justification = 'Global variables are used for module session helpers.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject[]],[string])]
    param(
        # URL Token from a secret
        [parameter(ValueFromPipeline)]
        [ValidateNotNullOrEmpty()]
        [string]
        $URLToken,

        # Return content of API call directly
        [Parameter()]
        [switch]
        $Raw
    )
    begin {
        if (-not $Global:PPPHeaders) { Write-Error 'Retrieving audit logs requires authentication. Run Initialize-PassPushPosh and pass your email address and API key before retrying.' -ErrorAction Stop -Category AuthenticationError }
    }
    process {
        try {
            $uri = "$Global:PPPBaseUrl/p/$URLToken/audit.json"
            Write-Debug 'Requesting $uri'
            $response = Invoke-WebRequest -Uri $uri -Method Get -Headers $Global:PPPHeaders -ErrorAction Stop
            if ([int]$response.StatusCode -eq 200 -and $response.Content -ieq "{`"error`":`"That push doesn't belong to you.`"}") {
                $result = [PSCustomObject]@{ 'Error' = "That Push doesn't belong to you"; 'ErrorCode' = 403 }
                Write-Warning $result.Error
                return $result
            }
            if ($Raw) { return $response.Content } else { return $response.Content | ConvertFrom-Json }
        }
        catch {
            Write-Verbose "An exception was caught: $($_.Exception.Message)"
            if ([int]$_.Exception.Response.StatusCode -eq 401) { # Could be optimized
                $result = [PSCustomObject]@{ 'Error' = 'Authentication error. Verify email address and API key.'; 'ErrorCode' = 401 }
                Write-Warning $result.Error
                return $result
            } elseif ([int]$_.Exception.Response.StatusCode -eq 404) {
                $result = [PSCustomObject]@{ 'Error' = 'Invalid token. Verify your Push URL token is correct.'; 'ErrorCode' = 404 }
                Write-Warning $result.Error
                return $result
            }
            elseif ($DebugPreference -eq [System.Management.Automation.ActionPreference]::Continue) {
                Set-Variable -Scope Global -Name 'PPPLastError' -Value $_
                Write-Debug -Message 'Response object set to global variable $PPPLastError'
                return [PSCustomObject]@{
                    'Error'        = $_.Exception.Message
                    'ErrorCode'    = [int]$_.Exception.Response.StatusCode
                    'ErrorMessage' = $_.Exception.Response.ReasonPhrase
                }
            }
        }
    }
}

# Invalid API key / email - 401
# Invalid URL Token - 404
# Valid token but not mine - 200, content =  {"error":"That push doesn't belong to you."}
# Success but no views - 200, content = : {"views":[]}
# Success with view history {"views":[{"ip":"75.118.137.58,172.70.135.200","user_agent":"Mozilla/5.0 (Macintosh; Darwin 21.6.0 Darwin Kernel Version 21.6.0: Mon Aug 22 20:20:05 PDT 2022; root:xnu-8020.140.49~2/RELEASE_ARM64_T8101; en-US) PowerShell/7.2.7","referrer":"","successful":true,"created_at":"2022-11-19T18:32:42.277Z","updated_at":"2022-11-19T18:32:42.277Z","kind":0}]}
# Content.Views
<#
ip         : 75.118.137.58,172.70.135.200
user_agent : Mozilla/5.0 (Macintosh; Darwin 21.6.0 Darwin Kernel Version 21.6.0: Mon Aug 22 20:20:05 PDT 2022; root:xnu-8020.140.49~2/RELEASE_ARM64_T8101;
en-US) PowerShell/7.2.7
referrer   :
successful : True
created_at : 11/19/2022 6:32:42 PM
updated_at : 11/19/2022 6:32:42 PM
kind       : 0
#>
function Get-SecretLink {
    <#
    .SYNOPSIS
    Returns a fully qualified secret link to a push of given URL Token

    .DESCRIPTION
    Accepts a string value for a URL Token and retrieves a full URL link to the secret.
    Returned value is a 1-step retrieval link depending on option selected during Push creation.
    Returns false if URL Token is invalid, however it will return a URL if the token is valid
    but the Push is expired or deleted.

    .INPUTS
    [string] URL Token value

    .OUTPUTS
    [string] Fully qualified URL
    [bool] $False if Push URL Token is invalid. Note: Expired or deleted Pushes will still return a link.

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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars','',Scope='Function',Justification='Global variables are used for module session helpers.')]
    [CmdletBinding()]
    [Alias('Get-PushPreview')]
    [OutputType('[string]')]
    param(
        # URL Token for the secret
        [parameter(Mandatory, ValueFromPipeline)]
        [ValidateLength(5, 256)]
        [string]$URLToken,

        # Return the raw response body from the API call
        [Parameter()]
        [switch]
        $Raw
    )
    begin { Initialize-PassPushPosh -Verbose:$VerbosePreference -Debug:$DebugPreference }
    process {
        try {
            $iwrSplat = @{
                'Method' = 'Get'
                'ContentType' = 'application/json'
                'Uri' = "$Global:PPPBaseUrl/p/$URLToken/preview.json"
                'UserAgent' = $Global:PPPUserAgent
            }
            if ($Global:PPPHeaders) { $iwrSplat['Headers'] = $Global:PPPHeaders }
            Write-Verbose "Sending HTTP request: $($iwrSplat | Out-String)"
            $responseContent = Invoke-WebRequest @iwrSplat | Select-Object -ExpandProperty Content
            if ($Raw) { return $responseContent }
            else { return $responseContent | ConvertFrom-Json | Select-Object -ExpandProperty url }
        }
        catch {
            Write-Verbose "An exception was caught: $($_.Exception.Message)"
            if ($DebugPreference -eq [System.Management.Automation.ActionPreference]::Continue) {
                Set-Variable -Scope Global -Name 'PPPLastError' -Value $_
                Write-Debug -Message 'Response object set to global variable $PPPLastError'
            }
        }
    }
}
function Initialize-PassPushPosh {
    <#
    .SYNOPSIS
    Initialize the PassPushPosh module

    .DESCRIPTION
    Sets global variables to handle the server URL and headers (authentication).
    Called automatically by module Functions if it is not called explicitly prior, so you don't actually need
    to call it unless you're going to use the authenticated API or alternate server, etc
    Default parameters use the pwpush.com domain and anonymous authentication.

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
    PS > InitializePassPushPosh -UserAgent "I'm a cool dude with a cool script."

    .LINK
    https://github.com/adamburley/PassPushPosh/blob/main/Docs/Initialize-PassPushPosh.md

    .NOTES
    All variables set by this function start with PPP.
    - PPPHeaders
    - PPPUserAgent
    - PPPBaseUrl

    -WhatIf setting for Set-Variable -Global is disabled, otherwise -WhatIf
    calls for other functions would return incorrect data in the case this
    function has not yet run.

    TODO: Review API key pattern for parameter validation
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars','',Scope='Function',Justification='Global variables are used for module session helpers.')]
    [CmdletBinding(DefaultParameterSetName='Anonymous')]
    param (
        # Email address to use for authenticated calls.
        [Parameter(Mandatory,Position=0,ParameterSetName='Authenticated')]
        [ValidatePattern('.+\@.+\..+')]
        [string]$EmailAddress,

        # API Key for authenticated calls.
        [Parameter(Mandatory,Position=1,ParameterSetName='Authenticated')]
        [ValidateLength(5,256)]
        [string]$ApiKey,

        # Base URL for API calls. Allows use of module with private instances of Password Pusher
        # Default: https://pwpush.com
        [Parameter(Position=0,ParameterSetName='Anonymous')]
        [Parameter(Position=2,ParameterSetName='Authenticated')]
        [ValidatePattern('^https?:\/\/[a-zA-Z0-9-_]+.[a-zA-Z0-9]+')]
        [string]$BaseUrl,

        # Set a specific user agent. Default user agent is a combination of the
        # module info, what your OS reports itself as, and a hash based on
        # your username + workstation or domain name. This way the UA can be
        # semi-consistent across sessions but not identifying.
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $UserAgent,

        # Force setting new information. If module is already initialized you can use this to
        # Re-initialize with default settings. Implied if either ApiKey or BaseUrl is provided.
        [Parameter()][switch]$Force
    )
    if ($Global:PPPBaseURL -and $true -inotin $Force, [bool]$ApiKey, [bool]$BaseUrl, [bool]$UserAgent) { Write-Debug -Message 'PassPushPosh is already initialized.' }
    else {
        $defaultBaseUrl = 'https://pwpush.com'
        $apiKeyOutput = if ($ApiKey) { 'x-' + $ApiKey.Substring($ApiKey.Length-4) } else { 'None' }

        if (-not $Global:PPPBaseURL) { # Not initialized
            if (-not $BaseUrl) { $BaseUrl = $defaultBaseUrl }
            Write-Verbose "Initializing PassPushPosh. ApiKey: [$apiKeyOutput], BaseUrl: $BaseUrl"
        } elseif ($Force -or $ApiKey -or $BaseURL) {
            if (-not $BaseUrl) { $BaseUrl = $defaultBaseUrl }
            $oldApiKeyOutput = if ($Global:PPPApiKey) { 'x-' + $Global:PPPApiKey.Substring($Global:PPPApiKey.Length-4) } else { 'None' }
            Write-Verbose "Re-initializing PassPushPosh. Old ApiKey: [$oldApiKeyOutput] New ApiKey: [$apiKeyOutput], Old BaseUrl: $Global:PPPBaseUrl New BaseUrl: $BaseUrl"
        }
        if ($PSCmdlet.ParameterSetName -eq 'Authenticated') {
            Set-Variable -Scope Global -Name PPPHeaders -WhatIf:$false -Value @{
                'X-User-Email' = $EmailAddress
                'X-User-Token' = $ApiKey
            }
        } elseif ($Global:PPPHeaders) { # Remove if present - covers case where module is reinitialized from an authenticated to an anonymous session
            Remove-Variable -Scope Global -Name PPPHeaders -WhatIf:$false
        }

        if (-not $UserAgent) {
            $osVersion = [System.Environment]::OSVersion
            $userAtDomain = "{0}@{1}" -f [System.Environment]::UserName, [System.Environment]::UserDomainName
            $uAD64 = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($userAtDomain))
            Write-Debug "$userAtDomain transformed to $uAD64. First 20 characters $($uAD64.Substring(0,20))"
            $UserAgent = "PassPushPosh/$((Get-Module -Name PassPushPosh).Version.ToString()) $osVersion/$($uAD64.Substring(0,20))"
            Write-Verbose "Generated user agent: $UserAgent"
        } else {
            Write-Verbose "Using specified user agent: $UserAgent"
        }

        Set-Variable -WhatIf:$false -Scope Global -Name PPPBaseURL -Value $BaseUrl.TrimEnd('/')
        Set-Variable -WhatIf:$false -Scope Global -Name PPPUserAgent -Value $UserAgent
    }
}
function New-PasswordPush {
    <#
    .SYNOPSIS
    Create a new blank Password Push object.

    .DESCRIPTION
    Creates a blank [PasswordPush].
    Generally not needed, use ConvertTo-PasswordPush
    See New-Push if you're trying to create a new secret to send

    .INPUTS
    None

    .OUTPUTS
    [PasswordPush]

    .EXAMPLE
    New-PasswordPush

    .LINK
    https://github.com/adamburley/PassPushPosh/blob/main/Docs/New-PasswordPush.md

    .NOTES
    TODO Rewrite - make this work including read-only properties
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Scope = 'Function', Justification = 'Creates a new object, no risk of overwriting data.')]
    [CmdletBinding()]
    param ()
    return [PasswordPush]::new()
}
function New-Push {
    <#
    .SYNOPSIS
    Create a new Password Push

    .DESCRIPTION
    Create a new Push on the specified Password Pusher instance. The
    programmatic equivalent of going to pwpush.com and entering info.
    Returns [PasswordPush] object. Link member is a link created based on
    1-step setting however both 1-step and direct links
    are always provided at LinkRetrievalStep and LinkDirect.

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

    .INPUTS
    [string]

    .OUTPUTS
    [PasswordPush] Push object
    [string] Raw result of API call

    .LINK
    https://github.com/adamburley/PassPushPosh/blob/main/Docs/New-Push.md

    .LINK
    https://pwpush.com/api/1.0/passwords/create.en.html

    .LINK
    Get-Push

    .NOTES
    Maximum for -ExpireAfterDays and -ExpireAfterViews is based on the default
    values for Password Pusher and what's used on the public instance
    (pwpush.com). If you're using this with a private instance and want to
    override that value you'll need to fork this module.

    TODO: Support [PasswordPush] input objects, testing
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars','',Scope='Function',Justification='Global variables are used for module session helpers.')]
    [CmdletBinding(SupportsShouldProcess,ConfirmImpact='Low',DefaultParameterSetName='Anonymous')]
    [OutputType([PasswordPush],[string],[bool])] # Returntype should be [PasswordPush] but I've yet to find a way to add class access to a function on a module...
    param(
        # The password or secret text to share.
        [Parameter(Mandatory=$true,ValueFromPipeline,Position=0)]
        [Alias('Password')]
        [ValidateNotNullOrEmpty()]
        [string]$Payload,

        # Label for this Push (requires Authenticated session)
        [Parameter(ParameterSetName='RequiresAuthentication')]
        [ValidateNotNullOrEmpty()]
        [string]$Note,

        # Expire secret link and delete after this many days.
        [Parameter()]
        [ValidateRange(1,90)]
        [int]
        $ExpireAfterDays,

        # Expire secret link after this many views.
        [Parameter()]
        [ValidateRange(1,100)]
        [int]
        $ExpireAfterViews,

        # Allow the recipient of a Push to delete it.
        [Parameter()]
        [switch]
        $DeletableByViewer,

        # Require recipient click an extra link to view Push payload.
        # Helps to avoid chat systems and URL scanners from eating up views.
        # Note that the retrieval step URL is always available for a push. This
        # parameter changes if the 1-click link is used in the Link parameter
        # and returned from the secret link helper (Get-SecretLink)
        [Parameter()]
        [switch]
        $RetrievalStep,

        # Return the raw response body from the API call
        [Parameter()]
        [switch]
        $Raw
    )

    begin {
        Initialize-PassPushPosh -Verbose:$VerbosePreference -Debug:$DebugPreference
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'RequiresAuthentication' -and -not $Global:PPPHeaders.'X-User-Token') { Write-Error -Message 'Setting a note requires an authenticated call.'; return $false }

        $body = @{
            'password' = @{
                'payload' = $Payload
            }
        }
        $shouldString = 'Submit {0} push with Payload of length {1}' -f $PSCmdlet.ParameterSetName, $Payload.Length
        if ($Note) {
            $body.password.note = $note
            $shouldString += " with note $note"
        }
        if ($ExpireAfterDays) {
            $body.password.expire_after_days = $ExpireAfterDays
            $shouldString += ', expire after {0} days' -f $ExpireAfterDays
        }
        if ($ExpireAfterViews) {
            $body.password.expire_after_views = $ExpireAfterViews
            $shouldString += ', expire after {0} views' -f $ExpireAfterViews
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
        if ($VerbosePreference -eq [System.Management.Automation.ActionPreference]::Continue) {
            # Sanitize input so we're not logging or outputting the payload
            $vBody = $body.Clone()
            $vBody.password.payload = "A payload of length $($body.password.payload.Length.ToString())"
            $vBs = $vBody | ConvertTo-Json | Out-String
            Write-Verbose "Call Body (sanitized): $vBs"
        }

        $iwrSplat = @{
            'Method' = 'Post'
            'ContentType' = 'application/json'
            'Body' = ($body | ConvertTo-Json)
            'Uri' = "$Global:PPPBaseUrl/p.json"
            'UserAgent' = $Global:PPPUserAgent
        }
        if ($Global:PPPHeaders.'X-User-Token') { $iwrSplat['Headers'] = $Global:PPPHeaders }
        Write-Verbose "Sending HTTP request (minus body): $($iwrSplat | Select-Object Method,ContentType,Uri,UserAgent,Headers | Out-String)"
        if ($PSCmdlet.ShouldProcess($shouldString, $iwrSplat.Uri, 'Submit new Push')) {
            try {
                $response = Invoke-WebRequest @iwrSplat
                if ($DebugPreference -eq [System.Management.Automation.ActionPreference]::Continue) {
                    Set-Variable -Scope Global -Name PPPLastCall -Value $response
                    Write-Debug 'Response to Invoke-WebRequest set to PPPLastCall Global variable'
                }
                if ($Raw) {
                    Write-Debug "Returning raw object: $($response.Content)"
                    return $response.Content
                }
                return $response.Content | ConvertTo-PasswordPush
            } catch {
                Write-Verbose "An exception was caught: $($_.Exception.Message)"
                if ($DebugPreference -eq [System.Management.Automation.ActionPreference]::Continue) {
                    Set-Variable -Scope Global -Name PPPLastError -Value $_
                    Write-Debug -Message 'Response object set to global variable $PPPLastError'
                }
            }
        }
    }
}
function Remove-Push {
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

    .INPUTS
    [string] URL Token
    [PasswordPush] representing the Push to remove

    .OUTPUTS
    [bool] True on success, otherwise False

    .EXAMPLE
    Remove-Push -URLToken bwzehzem_xu-

    .EXAMPLE
    Remove-Push -URLToken -Raw
    {"expired":true,"deleted":true,"expired_on":"2022-11-21T13:23:45.341Z","expire_after_days":1,"expire_after_views":4,"url_token":"bwzehzem_xu-","created_at":"2022-11-21T13:20:08.635Z","updated_at":"2022-11-21T13:23:45.342Z","deletable_by_viewer":true,"retrieval_step":false,"days_remaining":1,"views_remaining":4}

    .LINK
    https://github.com/adamburley/PassPushPosh/blob/main/Docs/Remove-Push.md

    .LINK
    https://pwpush.com/api/1.0/passwords/destroy.en.html

    .NOTES
    TODO testing and debugging
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars','',Scope='Function',Justification='Global variables are used for module session helpers.')]
    [CmdletBinding(SupportsShouldProcess,DefaultParameterSetName='Token')]
    [OutputType([PasswordPush],[string],[bool])]
    param(
        # URL Token for the secret
        [parameter(ValueFromPipeline,ParameterSetName='Token')]
        [ValidateNotNullOrEmpty()]
        [Alias('Token')]
        [string]
        $URLToken,

        # PasswordPush object
        [Parameter(ValueFromPipeline,ParameterSetName='Object')]
        [PasswordPush]
        $PushObject,

        # Return the raw response body from the API call
        [parameter()]
        [switch]
        $Raw
    )
    process {
        try {
            if ($PSCmdlet.ParameterSetName -eq 'Object') {
                Write-Debug -Message "Remove-Push was passed a PasswordPush object with URLToken: [$($PushObject.URLToken)]"
                if (-not $PushObject.IsDeletableByViewer -and -not $Global:PPPHeaders) { #Pre-qualify if this will succeed
                    Write-Warning -Message 'Unable to remove Push. Push is not marked as deletable by viewer and you are not authenticated.'
                    return $false
                }
                if ($PushObject.IsDeletableByViewer) {
                    Write-Verbose "Push is flagged as deletable by viewer, should be deletable."
                } else { Write-Verbose "In an authenticated API session. Push will be deletable if it was created by authenticated user." }
                $URLToken = $PushObject.URLToken
            } else {
                Write-Debug -Message "Remove-Push was passed a URLToken: [$URLToken]"
            }
            Write-Verbose -Message "Push with URL Token [$URLToken] will be deleted if 'Deletable by viewer' was enabled or you are the creator of the push and are authenticated."
            $iwrSplat = @{
                'Method' = 'Delete'
                'ContentType' = 'application/json'
                'Uri' = "$Global:PPPBaseUrl/p/$URLToken.json"
                'UserAgent' = $Global:PPPUserAgent
            }
            if ($Global:PPPHeaders) { $iwrSplat['Headers'] = $Global:PPPHeaders }
            Write-Verbose "Sending HTTP request: $($iwrSplat | Out-String)"
            if ($PSCmdlet.ShouldProcess('Delete',"Push with token [$URLToken]")) {
                $response = Invoke-WebRequest @iwrSplat
                if ($DebugPreference -eq [System.Management.Automation.ActionPreference]::Continue) {
                    Set-Variable -Scope Global -Name PPPLastCall -Value $response
                    Write-Debug 'Response to Invoke-WebRequest set to PPPLastCall Global variable'
                }
                if ($Raw) {
                    Write-Debug "Returning raw object: $($response.Content)"
                    return $response.Content
                }
                return $response.Content | ConvertTo-PasswordPush
            }
        } catch {
            if ($_.Exception.Response.StatusCode -eq 404) {
            Write-Warning "Failed to delete Push. This can indicate an invalid URL Token, that the password was not marked deletable, or that you are not the owner."
            return $false
            } else {
                Write-Verbose "An exception was caught: $($_.Exception.Message)"
                if ($DebugPreference -eq [System.Management.Automation.ActionPreference]::Continue) {
                    Set-Variable -Scope Global -Name PPPLastError -Value $_
                    Write-Debug -Message 'Response object set to global variable $PPPLastError'
                }
                $_
            }
        }
    }
}
