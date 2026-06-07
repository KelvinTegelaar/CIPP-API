#Region './Classes/AliasVisitor.ps1' -1

using namespace System.Management.Automation.Language
using namespace System.Collections.Generic

# This is used only to parse the parameters to New|Set|Remove-Alias
# NOTE: this is _part of_ the implementation of AliasVisitor, but ...
#       PowerShell can't handle nested classes so I left it outside,
#       but I kept it here in this file.
class AliasParameterVisitor : AstVisitor {
    [string]$Parameter = $null
    [string]$Command = $null
    [string]$Name = $null
    [string]$Value = $null
    [string]$Scope = $null

    # Parameter Names
    [AstVisitAction] VisitCommandParameter([CommandParameterAst]$ast) {
        $this.Parameter = $ast.ParameterName
        return [AstVisitAction]::Continue
    }

    # Parameter Values
    [AstVisitAction] VisitStringConstantExpression([StringConstantExpressionAst]$ast) {
        # The FIRST command element is always the command name
        if (!$this.Command) {
            $this.Command = $ast.Value
            return [AstVisitAction]::Continue
        } else {
            # Nobody should use minimal parameters like -N for -Name ...
            # But if they do, our parser works anyway!
            switch -Wildcard ($this.Parameter) {
                "S*" {
                    $this.Scope = $ast.Value
                }
                "N*" {
                    $this.Name = $ast.Value
                }
                "Va*" {
                    $this.Value = $ast.Value
                }
                "F*" {
                    if ($ast.Value) {
                        # Force parameter was passed as named parameter with a positional parameter after it which is alias name
                        $this.Name = $ast.Value
                    }
                }
                default {
                    if (!$this.Parameter) {
                        # For bare arguments, the order is Name, Value:
                        if (!$this.Name) {
                            $this.Name = $ast.Value
                        } else {
                            $this.Value = $ast.Value
                        }
                    }
                }
            }

            $this.Parameter = $null

            # If we have enough information, stop the visit
            # For -Scope global or Remove-Alias, we don't want to export these
            if ($this.Name -and $this.Command -eq "Remove-Alias") {
                $this.Command = "Remove-Alias"
                return [AstVisitAction]::StopVisit
            } elseif ($this.Name -and $this.Scope -eq "Global") {
                return [AstVisitAction]::StopVisit
            }
            return [AstVisitAction]::Continue
        }
    }

    [AliasParameterVisitor] Clear() {
        $this.Command = $null
        $this.Parameter = $null
        $this.Name = $null
        $this.Value = $null
        $this.Scope = $null
        return $this
    }
}

# This visits everything at the top level of the script
class AliasVisitor : AstVisitor {
    [HashSet[String]]$Aliases = @()
    [AliasParameterVisitor]$Parameters = @{}

    # The [Alias(...)] attribute on functions matters, but we can't export aliases that are defined inside a function
    [AstVisitAction] VisitFunctionDefinition([FunctionDefinitionAst]$ast) {
        @($ast.Body.ParamBlock.Attributes.Where{
            $_.TypeName.Name -eq "Alias"
        }.PositionalArguments.Value).ForEach{
            if ($_) {
                $this.Aliases.Add($_)
            }
        }

        return [AstVisitAction]::SkipChildren
    }

    # Top-level commands matter, but only if they're alias commands
    [AstVisitAction] VisitCommand([CommandAst]$ast) {
        if ($ast.CommandElements[0].Value -imatch "(New|Set|Remove)-Alias") {
            $ast.Visit($this.Parameters.Clear())

            # We COULD just remove it (even if we didn't add it) ...
            if ($this.Parameters.Command -ieq "Remove-Alias") {
                # But Write-Verbose for logging purposes
                if ($this.Aliases.Contains($this.Parameters.Name)) {
                    Write-Verbose -Message "Alias '$($this.Parameters.Name)' is removed by line $($ast.Extent.StartLineNumber): $($ast.Extent.Text)"
                    $this.Aliases.Remove($this.Parameters.Name)
                }
            # We don't need to export global aliases, because they broke out already
            } elseif ($this.Parameters.Name -and $this.Parameters.Scope -ine 'Global') {
                $this.Aliases.Add($this.Parameters.Name)
            }
        }
        return [AstVisitAction]::SkipChildren
    }
}
#EndRegion './Classes/AliasVisitor.ps1' 120
#Region './Private/ConvertToAst.ps1' -1

function ConvertToAst {
    <#
        .SYNOPSIS
            Parses the given code and returns an object with the AST, Tokens and ParseErrors
    #>
    param(
        # The script content, or script or module file path to parse
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias("Path", "PSPath", "Definition", "ScriptBlock", "Module")]
        $Code
    )
    process {
        Write-Debug "    ENTER: ConvertToAst $Code"
        $ParseErrors = $null
        $Tokens = $null
        if ($Code | Test-Path -ErrorAction SilentlyContinue) {
            Write-Debug "      Parse Code as Path"
            $AST = [System.Management.Automation.Language.Parser]::ParseFile(($Code | Convert-Path), [ref]$Tokens, [ref]$ParseErrors)
        } elseif ($Code -is [System.Management.Automation.FunctionInfo]) {
            Write-Debug "      Parse Code as Function"
            $String = "function $($Code.Name) { $($Code.Definition) }"
            $AST = [System.Management.Automation.Language.Parser]::ParseInput($String, [ref]$Tokens, [ref]$ParseErrors)
        } else {
            Write-Debug "      Parse Code as String"
            $AST = [System.Management.Automation.Language.Parser]::ParseInput([String]$Code, [ref]$Tokens, [ref]$ParseErrors)
        }

        Write-Debug "    EXIT: ConvertToAst"
        [PSCustomObject]@{
            PSTypeName  = "PoshCode.ModuleBuilder.ParseResults"
            ParseErrors = $ParseErrors
            Tokens      = $Tokens
            AST         = $AST
        }
    }
}
#EndRegion './Private/ConvertToAst.ps1' 37
#Region './Private/CopyReadMe.ps1' -1

function CopyReadMe {
    [CmdletBinding()]
    param(
        # The path to the ReadMe document to copy
        [Parameter(ValueFromPipelineByPropertyName)]
        [AllowNull()][AllowEmptyString()]
        [string]$ReadMe,

        # The name of the module -- because the file is renamed to about_$ModuleName.help.txt
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]
        [Alias("Name")]
        [string]$ModuleName,

        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]
        [string]$OutputDirectory,

        # The culture (language) to store the ReadMe as (defaults to "en")
        [Parameter(ValueFromPipelineByPropertyName)]
        [Globalization.CultureInfo]$Culture = $(Get-UICulture),

        # If set, overwrite the existing readme
        [Switch]$Force
    )
    process {
        # Copy the readme file as an about_ help file
        Write-Verbose "Test for ReadMe: $Pwd/$($ReadMe)"
        if ($ReadMe -and (Test-Path $ReadMe -PathType Leaf)) {
            # Make sure there's a language path
            $LanguagePath = Join-Path $OutputDirectory $Culture
            if (!(Test-Path $LanguagePath -PathType Container)) {
                $null = New-Item $LanguagePath -Type Directory -Force
            }
            Write-Verbose "Copy ReadMe to: $LanguagePath"

            $about_module = Join-Path $LanguagePath "about_$($ModuleName).help.txt"
            if (!(Test-Path $about_module)) {
                Write-Verbose "Turn readme into about_module"
                Copy-Item -LiteralPath $ReadMe -Destination $about_module -Force:$Force
            }
        }
    }
}
#EndRegion './Private/CopyReadMe.ps1' 43
#Region './Private/GetBuildInfo.ps1' -1

function GetBuildInfo {
    [CmdletBinding()]
    param(
        # The path to the Build Manifest Build.psd1
        [Parameter()]
        [AllowNull()]
        [string]$BuildManifest,

        # Pass MyInvocation from the Build-Command so we can read parameter values
        [Parameter(DontShow)]
        [AllowNull()]
        $BuildCommandInvocation
    )

    $BuildInfo = if ($BuildManifest -and (Test-Path $BuildManifest) -and (Split-path -Leaf $BuildManifest) -eq 'build.psd1') {
        # Read the build.psd1 configuration file for default parameter values
        Write-Debug "Load Build Manifest $BuildManifest"
        Import-Metadata -Path $BuildManifest
    } else {
        @{}
    }

    $CommonParameters = [System.Management.Automation.Cmdlet]::CommonParameters +
                        [System.Management.Automation.Cmdlet]::OptionalCommonParameters
    $BuildParameters = $BuildCommandInvocation.MyCommand.Parameters
    # Make we can always look things up in BoundParameters
    $BoundParameters = if ($BuildCommandInvocation.BoundParameters) {
        $BuildCommandInvocation.BoundParameters
    } else {
        @{}
    }

    # Combine the defaults with parameter values
    $ParameterValues = @{}
    if ($BuildCommandInvocation) {
        foreach ($parameter in $BuildParameters.GetEnumerator().Where({$_.Key -notin $CommonParameters})) {
            Write-Debug "  Parameter: $($parameter.key)"
            $key = $parameter.Key

            # We want to map the parameter aliases to the parameter name:
            foreach ($k in @($parameter.Value.Aliases)) {
                if ($null -ne $k -and $BuildInfo.ContainsKey($k)) {
                    Write-Debug "    ... Update BuildInfo[$key] from $k"
                    $BuildInfo[$key] = $BuildInfo[$k]
                    $null = $BuildInfo.Remove($k)
                }
            }
            # Bound parameter values > build.psd1 values > default parameters values
            if (-not $BuildInfo.ContainsKey($key) -or $BoundParameters.ContainsKey($key)) {
                # Reading the current value of the $key variable returns either the bound parameter or the default
                if ($null -ne ($value = Get-Variable -Name $key -ValueOnly -ErrorAction Ignore )) {
                    if ($value -ne ($null -as $parameter.Value.ParameterType)) {
                        $ParameterValues[$key] = $value
                    }
                }
                if ($BoundParameters.ContainsKey($key)) {
                    Write-Debug "    From Parameter: $($ParameterValues[$key] -join ', ')"
                } elseif ($ParameterValues[$key]) {
                    Write-Debug "    From Default: $($ParameterValues[$key] -join ', ')"
                }
            } elseif ($BuildInfo[$key]) {
                Write-Debug "    From Manifest: $($BuildInfo[$key] -join ', ')"
            }
        }
    }
    # BuildInfo.SourcePath should point to a module manifest
    if ($BuildInfo.SourcePath -and $BuildInfo.SourcePath -ne $BuildManifest) {
        Write-Debug "  Updating: SourcePath"
        Write-Debug "    To: $($BuildInfo.SourcePath)"
        $ParameterValues["SourcePath"] = $BuildInfo.SourcePath
    }
    # If SourcePath point to build.psd1, we should clear it
    if ($ParameterValues["SourcePath"] -eq $BuildManifest) {
        Write-Debug "  Removing: SourcePath"
        $ParameterValues.Remove("SourcePath")
    }
    Write-Debug "Finished parsing Build Manifest $BuildManifest"

    $BuildManifestParent = if ($BuildManifest) {
        Split-Path -Parent $BuildManifest
    } else {
        Get-Location -PSProvider FileSystem
    }

    if ((-not $BuildInfo.SourcePath) -and $ParameterValues["SourcePath"] -notmatch '\.psd1') {
        Write-Debug "  Searching: SourcePath ($BuildManifestParent/**/*.psd1)"
        # Find a module manifest (or maybe several)
        $ModuleInfo = Get-ChildItem $BuildManifestParent -Recurse -Filter *.psd1 -ErrorAction SilentlyContinue |
            ImportModuleManifest -ErrorAction SilentlyContinue
        # If we found more than one module info, the only way we have of picking just one is if it matches a folder name
        if (@($ModuleInfo).Count -gt 1) {
            Write-Debug (@(@("  Found $(@($ModuleInfo).Count):") + @($ModuleInfo.Path)) -join "`n            ")
            # It can't be a module that needs building unless it has either:
            $ModuleInfo = $ModuleInfo.Where{
                $Root = Split-Path $_.Path
                @(
                    # - A build.psd1 next to it
                    Test-Path (Join-Path $Root "build.ps1") -PathType Leaf
                    # - A Public (or Private) folder with source scripts in it
                    Test-Path (Join-Path $Root "Public") -PathType Container
                    Test-Path (Join-Path $Root "Private") -PathType Container
                ) -contains $true
            }
            Write-Debug (@(@("  Filtered $(@($ModuleInfo).Count):") + @($ModuleInfo.Path)) -join "`n            ")
        }
        if (@($ModuleInfo).Count -eq 1) {
            Write-Debug "Updating BuildInfo SourcePath to $($ModuleInfo.Path)"
            $ParameterValues["SourcePath"] = $ModuleInfo.Path
        } else {
            throw "Can't determine the module manifest in $BuildManifestParent"
        }
    }

    $BuildInfo = $BuildInfo | Update-Object $ParameterValues
    Write-Debug "Using Module Manifest $($BuildInfo.SourcePath)"

    # Make sure the SourcePath is absolute and points at an actual file
    if (!(Split-Path -IsAbsolute $BuildInfo.SourcePath) -and $BuildManifestParent) {
        $BuildInfo.SourcePath = Join-Path $BuildManifestParent $BuildInfo.SourcePath | Convert-Path
    } else {
        $BuildInfo.SourcePath = Convert-Path $BuildInfo.SourcePath
    }
    if (!(Test-Path $BuildInfo.SourcePath)) {
        throw "Can't find module manifest at the specified SourcePath: $($BuildInfo.SourcePath)"
    }

    $BuildInfo
}
#EndRegion './Private/GetBuildInfo.ps1' 129
#Region './Private/GetCommandAlias.ps1' -1


function GetCommandAlias {
    <#
        .SYNOPSIS
            Parses one or more files for aliases and returns a list of alias names.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.Hashset[string]])]
    param(
        # The AST to find aliases in
        [Parameter(Mandatory, ValueFromPipelineByPropertyName, ValueFromPipeline)]
        [System.Management.Automation.Language.Ast]$Ast
    )
    begin {
        $Visitor = [AliasVisitor]::new()
    }
    process {
        $Ast.Visit($Visitor)
    }
    end {
        $Visitor.Aliases
    }
}

#EndRegion './Private/GetCommandAlias.ps1' 25
#Region './Private/GetRelativePath.ps1' -1

function GetRelativePath {
    <#
        .SYNOPSIS
            Returns the relative path, or $Path if the paths don't share the same root.
            For backward compatibility, this is [System.IO.Path]::GetRelativePath for .NET 4.x
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        # The source path the result should be relative to. This path is always considered to be a directory.
        [Parameter(Mandatory)]
        [string]$RelativeTo,

        # The destination path.
        [Parameter(Mandatory)]
        [string]$Path
    )

    # This giant mess is because PowerShell drives aren't valid filesystem drives
    $Drive = $Path -replace "^([^\\/]+:[\\/])?.*", '$1'
    if ($Drive -ne ($RelativeTo -replace "^([^\\/]+:[\\/])?.*", '$1')) {
        Write-Verbose "Paths on different drives"
        return $Path # no commonality, different drive letters on windows
    }
    $RelativeTo = $RelativeTo -replace "^[^\\/]+:[\\/]", [IO.Path]::DirectorySeparatorChar
    $Path = $Path -replace "^[^\\/]+:[\\/]", [IO.Path]::DirectorySeparatorChar
    $RelativeTo = [IO.Path]::GetFullPath($RelativeTo).TrimEnd('\/') -replace "^[^\\/]+:[\\/]", [IO.Path]::DirectorySeparatorChar
    $Path = [IO.Path]::GetFullPath($Path) -replace "^[^\\/]+:[\\/]", [IO.Path]::DirectorySeparatorChar

    $commonLength = 0
    while ($Path[$commonLength] -eq $RelativeTo[$commonLength]) {
        $commonLength++
    }
    if ($commonLength -eq $RelativeTo.Length -and $RelativeTo.Length -eq $Path.Length) {
        Write-Verbose "Equal Paths"
        return "." # The same paths
    }
    if ($commonLength -eq 0) {
        Write-Verbose "Paths on different drives?"
        return $Drive + $Path # no commonality, different drive letters on windows
    }

    Write-Verbose "Common base: $commonLength $($RelativeTo.Substring(0,$commonLength))"
    # In case we matched PART of a name, like C:\Users\Joel and C:\Users\Joe
    while ($commonLength -gt $RelativeTo.Length -and ($RelativeTo[$commonLength] -ne [IO.Path]::DirectorySeparatorChar)) {
        $commonLength--
    }

    Write-Verbose "Common base: $commonLength $($RelativeTo.Substring(0,$commonLength))"
    # create '..' segments for segments past the common on the "$RelativeTo" path
    if ($commonLength -lt $RelativeTo.Length) {
        $result = @('..') * @($RelativeTo.Substring($commonLength).Split([IO.Path]::DirectorySeparatorChar).Where{ $_ }).Length -join ([IO.Path]::DirectorySeparatorChar)
    }
    (@($result, $Path.Substring($commonLength).TrimStart([IO.Path]::DirectorySeparatorChar)).Where{ $_ } -join ([IO.Path]::DirectorySeparatorChar))
}
#EndRegion './Private/GetRelativePath.ps1' 56
#Region './Private/ImportModuleManifest.ps1' -1

function ImportModuleManifest {
    [CmdletBinding()]
    param(
        [Alias("PSPath")]
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Path
    )
    process {
        # Get all the information in the module manifest
        $ModuleInfo = Get-Module $Path -ListAvailable -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Problems

        # Some versions fails silently. If the GUID is empty, we didn't get anything at all
        if ($ModuleInfo.Guid -eq [Guid]::Empty) {
            Write-Error "Cannot parse '$Path' as a module manifest, try Test-ModuleManifest for details"
            return
        }

        # Some versions show errors are when the psm1 doesn't exist (yet), but we don't care
        $ErrorsWeIgnore = "^" + (@(
            "Modules_InvalidRequiredModulesinModuleManifest"
            "Modules_InvalidRootModuleInModuleManifest"
        ) -join "|^")

        # If there are any OTHER problems we'll fail
        if ($Problems = $Problems.Where({ $_.FullyQualifiedErrorId -notmatch $ErrorsWeIgnore })) {
            foreach ($problem in $Problems) {
                Write-Error $problem
            }
            # Short circuit - don't output the ModuleInfo if there were errors
            return
        }

        # Workaround the fact that Get-Module returns the DefaultCommandPrefix as Prefix
        Update-Object -InputObject $ModuleInfo -UpdateObject @{ DefaultCommandPrefix = $ModuleInfo.Prefix; Prefix = "" }
    }
}
#EndRegion './Private/ImportModuleManifest.ps1' 37
#Region './Private/InitializeBuild.ps1' -1

function InitializeBuild {
    <#
        .SYNOPSIS
            Loads build.psd1 and the module manifest and combines them with the parameter values of the calling function.
        .DESCRIPTION
            This function is for internal use from Build-Module only
            It does a few things that make it really only work properly there:

            1. It calls ResolveBuildManifest to resolve the Build.psd1 from the given -SourcePath (can be Folder, Build.psd1 or Module manifest path)
            2. Then calls GetBuildInfo to read the Build configuration file and override parameters passed through $Invocation (read from the PARENT MyInvocation)
            2. It gets the Module information from the ModuleManifest, and merges it with the $ModuleInfo
        .NOTES
            Depends on the Configuration module Update-Object and (the built in Import-LocalizedData and Get-Module)
    #>
    [CmdletBinding()]
    param(
        # The root folder where the module source is (including the Build.psd1 and the module Manifest.psd1)
        [string]$SourcePath,

        [Parameter(DontShow)]
        [AllowNull()]
        $BuildCommandInvocation = $(Get-Variable MyInvocation -Scope 1 -ValueOnly)
    )
    Write-Debug "Initializing build variables"

    # GetBuildInfo reads the parameter values from the Build-Module command and combines them with the Manifest values
    $BuildManifest = ResolveBuildManifest $SourcePath

    Write-Debug "BuildCommand: $(
        @(
            @($BuildCommandInvocation.MyCommand.Name)
            @($BuildCommandInvocation.BoundParameters.GetEnumerator().ForEach{ "-{0} '{1}'" -f $_.Key, $_.Value })
        ) -join ' ')"
    $BuildInfo = GetBuildInfo -BuildManifest $BuildManifest -BuildCommandInvocation $BuildCommandInvocation

    # Normalize the version (if it was passed in via build.psd1)
    if ($BuildInfo.SemVer) {
        Write-Verbose "Update the Version, Prerelease, and BuildMetadata from the SemVer (in case it was passed in via build.psd1)"
        $BuildInfo = $BuildInfo | Update-Object @{
            Prerelease    = $BuildInfo.SemVer.Split("+")[0].Split("-", 2)[1]
            BuildMetadata = $BuildInfo.SemVer.Split("+", 2)[1]
            Version       = if (($V = $BuildInfo.SemVer.Split("+")[0].Split("-", 2)[0])) {
                [version]$V
            }
        }
    } elseif($BuildInfo.Version) {
        Write-Verbose "Calculate the Semantic Version from the Version - Prerelease + BuildMetadata"
        $SemVer = "$($BuildInfo.Version)"
        if ($BuildInfo.Prerelease) {
            $SemVer = "$SemVer-$($BuildInfo.Prerelease)"
        }
        if ($BuildInfo.BuildMetadata) {
            $SemVer = "$SemVer+$($BuildInfo.BuildMetadata)"
        }
        $BuildInfo = $BuildInfo | Update-Object @{ SemVer = $SemVer }
    }

    # Override VersionedOutputDirectory with UnversionedOutputDirectory
    if ($BuildInfo.UnversionedOutputDirectory -and $BuildInfo.VersionedOutputDirectory) {
        $BuildInfo.VersionedOutputDirectory = $false
    }

    # Finally, add all the information in the module manifest to the return object
    if ($ModuleInfo = ImportModuleManifest $BuildInfo.SourcePath) {
        # Update the module manifest with our build configuration and output it
        Update-Object -InputObject $ModuleInfo -UpdateObject $BuildInfo
    } else {
        throw "Unresolvable problems in module manifest: '$($BuildInfo.SourcePath)'"
    }
}
#EndRegion './Private/InitializeBuild.ps1' 71
#Region './Private/MoveUsingStatements.ps1' -1

function MoveUsingStatements {
    <#
        .SYNOPSIS
            A command to comment out and copy to the top of the file the Using Statements
        .DESCRIPTION
            When all files are merged together, the Using statements from individual files
            don't  necessarily end up at the beginning of the PSM1, creating Parsing Errors.

            This function uses AST to comment out those statements (to preserver line numbering)
            and insert them (conserving order) at the top of the script.
    #>
    [CmdletBinding()]
    param(
        # Path to the PSM1 file to amend
        [Parameter(Mandatory, ValueFromPipelineByPropertyName, ValueFromPipeline)]
        [System.Management.Automation.Language.Ast]$AST,

        [Parameter(ValueFromPipelineByPropertyName, ValueFromPipeline)]
        [AllowNull()]
        [System.Management.Automation.Language.ParseError[]]$ParseErrors,

        # The encoding defaults to UTF8 (or UTF8NoBom on Core)
        [Parameter(DontShow)]
        [string]$Encoding = $(if ($IsCoreCLR) {
                "UTF8NoBom"
            } else {
                "UTF8"
            })
    )
    process {
        # Avoid modifying the file if there's no Parsing Error caused by Using Statements or other errors
        if (!$ParseErrors.Where{ $_.ErrorId -eq 'UsingMustBeAtStartOfScript' }) {
            Write-Debug "No using statement errors found."
            return
        } else {
            # as decided https://github.com/PoshCode/ModuleBuilder/issues/96
            Write-Debug "Parsing errors found. We'll still attempt to Move using statements."
        }

        # Find all Using statements including those non erroring (to conserve their order)
        $UsingStatementExtents = $AST.FindAll(
            { $Args[0] -is [System.Management.Automation.Language.UsingStatementAst] },
            $false
        ).Extent

        # Edit the Script content by commenting out existing statements (conserving line numbering)
        $ScriptText = $AST.Extent.Text
        $InsertedCharOffset = 0
        $StatementsToCopy = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

        foreach ($UsingSatement in $UsingStatementExtents) {
            $ScriptText = $ScriptText.Insert($UsingSatement.StartOffset + $InsertedCharOffset, '#')
            $InsertedCharOffset++

            # Keep track of unique statements we'll need to insert at the top
            $null = $StatementsToCopy.Add($UsingSatement.Text)
        }

        $ScriptText = $ScriptText.Insert(0, ($StatementsToCopy -join "`r`n") + "`r`n")
        $null = Set-Content -Value $ScriptText -Path $RootModule -Encoding $Encoding

        # Verify we haven't introduced new Parsing errors
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            $RootModule,
            [ref]$null,
            [ref]$ParseErrors
        )

        if ($ParseErrors.Count) {
            $Message = $ParseErrors |
                Format-Table -Auto @{n = "File"; expr = { $_.Extent.File | Split-Path -Leaf }},
                                @{n = "Line"; expr = { $_.Extent.StartLineNumber }},
                                Extent, ErrorId, Message | Out-String
            Write-Warning "Parse errors in build output:`n$Message"
        }
    }
}
#EndRegion './Private/MoveUsingStatements.ps1' 78
#Region './Private/ParameterValues.ps1' -1

Update-TypeData -TypeName System.Management.Automation.InvocationInfo -MemberName ParameterValues -MemberType ScriptProperty -Value {
    $results = @{}
    foreach ($key in $this.MyCommand.Parameters.Keys) {
        if ($this.BoundParameters.ContainsKey($key)) {
            $results.$key = $this.BoundParameters.$key
        } elseif ($value = Get-Variable -Name $key -Scope 1 -ValueOnly -ErrorAction Ignore) {
            $results.$key = $value
        }
    }
    return $results
} -Force
#EndRegion './Private/ParameterValues.ps1' 12
#Region './Private/ParseLineNumber.ps1' -1

function ParseLineNumber {
    <#
        .SYNOPSIS
            Parses the SourceFile and SourceLineNumber from a position message
        .DESCRIPTION
            Parses messages like:
                at <ScriptBlock>, <No file>: line 1
                at C:\Test\Path\ErrorMaker.ps1:31 char:1
                at C:\Test\Path\Modules\ErrorMaker\ErrorMaker.psm1:27 char:4
    #>
    [Cmdletbinding()]
    param(
        # A position message, starting with "at ..." and containing a line number
        [Parameter(ValueFromPipeline)]
        [string]$PositionMessage
    )
    process {
        foreach($line in $PositionMessage -split "\r?\n") {
            # At (optional invocation,) <source file>:(maybe " line ") number
            if ($line -match "at(?: (?<InvocationBlock>[^,]+),)?\s+(?<SourceFile>.+):(?<!char:)(?: line )?(?<SourceLineNumber>\d+)(?: char:(?<OffsetInLine>\d+))?") {
                [PSCustomObject]@{
                    PSTypeName       = "Position"
                    SourceFile       = $matches.SourceFile
                    SourceLineNumber = $matches.SourceLineNumber
                    OffsetInLine     = $matches.OffsetInLine
                    PositionMessage  = $line
                    PSScriptRoot     = Split-Path $matches.SourceFile
                    PSCommandPath    = $matches.SourceFile
                    InvocationBlock  = $matches.InvocationBlock
                }
            } elseif($line -notmatch "\s*\+") {
                Write-Warning "Can't match: '$line'"
            }
        }
    }
}
#EndRegion './Private/ParseLineNumber.ps1' 37
#Region './Private/ResolveBuildManifest.ps1' -1

function ResolveBuildManifest {
    [CmdletBinding()]
    param(
        # The Source folder path, the Build Manifest Path, or the Module Manifest path used to resolve the Build.psd1
        [Alias("BuildManifest")]
        [string]$SourcePath = $(Get-Location -PSProvider FileSystem)
    )
    Write-Debug "ResolveBuildManifest $SourcePath"
    if ((Split-Path $SourcePath -Leaf) -eq 'build.psd1') {
        $BuildManifest = $SourcePath
    } elseif (Test-Path $SourcePath -PathType Leaf) {
        # When you pass the SourcePath as parameter, you must have the Build Manifest in the same folder
        $BuildManifest = Join-Path (Split-Path -Parent $SourcePath) [Bb]uild.psd1
    } else {
        # It's a container, assume the Build Manifest is directly under
        $BuildManifest = Join-Path $SourcePath [Bb]uild.psd1
    }

    # Make sure we are resolving the absolute path to the manifest, and test it exists
    $ResolvedBuildManifest = (Resolve-Path $BuildManifest -ErrorAction SilentlyContinue).Path

    if ($ResolvedBuildManifest) {
        $ResolvedBuildManifest
    }

}
#EndRegion './Private/ResolveBuildManifest.ps1' 27
#Region './Private/ResolveOutputFolder.ps1' -1

function ResolveOutputFolder {
    [CmdletBinding()]
    param(
        # The name of the module to build
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias("Name")]
        [string]$ModuleName,

        # Where to resolve the $OutputDirectory from when relative
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias("ModuleBase")]
        [string]$Source,

        # Where to build the module.
        # Defaults to an \output folder, adjacent to the "SourcePath" folder
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$OutputDirectory,

        # specifies the module version for use in the output path if -VersionedOutputDirectory is true
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias("ModuleVersion")]
        [string]$Version,

        # If set (true) adds a folder named after the version number to the OutputDirectory
        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias("Force")]
        [switch]$VersionedOutputDirectory,

        # Controls whether or not there is a build or cleanup performed
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [ValidateSet("Clean", "Build", "CleanBuild")]
        [string]$Target = "CleanBuild"
    )
    process {
        Write-Verbose "Resolve OutputDirectory path: $OutputDirectory"

        # Ensure the OutputDirectory makes sense (it's never blank anymore)
        if (!(Split-Path -IsAbsolute $OutputDirectory)) {
            # Relative paths are relative to the ModuleBase
            $OutputDirectory = Join-Path $Source $OutputDirectory
        }
        # If they passed in a path with ModuleName\Version on the end...
        if ((Split-Path $OutputDirectory -Leaf).EndsWith($Version) -and (Split-Path (Split-Path $OutputDirectory) -Leaf) -eq $ModuleName) {
            # strip the version (so we can add it back)
            $VersionedOutputDirectory = $true
            $OutputDirectory = Split-Path $OutputDirectory
        }
        # Ensure the OutputDirectory is named "ModuleName"
        if ((Split-Path $OutputDirectory -Leaf) -ne $ModuleName) {
            # If it wasn't, add a "ModuleName"
            $OutputDirectory = Join-Path $OutputDirectory $ModuleName
        }
        # Ensure the OutputDirectory is not a parent of the SourceDirectory
        $RelativeOutputPath = GetRelativePath $OutputDirectory $Source
        if (-not $RelativeOutputPath.StartsWith("..") -and $RelativeOutputPath -ne $Source) {
            Write-Verbose "Added Version to OutputDirectory path: $OutputDirectory"
            $OutputDirectory = Join-Path $OutputDirectory $Version
        }
        # Ensure the version number is on the OutputDirectory if it's supposed to be
        if ($VersionedOutputDirectory -and -not (Split-Path $OutputDirectory -Leaf).EndsWith($Version)) {
            Write-Verbose "Added Version to OutputDirectory path: $OutputDirectory"
            $OutputDirectory = Join-Path $OutputDirectory $Version
        }

        if (Test-Path $OutputDirectory -PathType Leaf) {
            throw "Unable to build. There is a file in the way at $OutputDirectory"
        }

        if ($Target -match "Clean") {
            Write-Verbose "Cleaning $OutputDirectory"
            if (Test-Path $OutputDirectory -PathType Container) {
                Remove-Item $OutputDirectory -Recurse -Force
            }
        }
        if ($Target -match "Build") {
            # Make sure the OutputDirectory exists (relative to ModuleBase or absolute)
            New-Item $OutputDirectory -ItemType Directory -Force | Convert-Path
        }
    }
}
#EndRegion './Private/ResolveOutputFolder.ps1' 81
#Region './Private/SetModuleContent.ps1' -1

function SetModuleContent {
    <#
        .SYNOPSIS
            A wrapper for Set-Content that handles arrays of file paths
        .DESCRIPTION
            The implementation here is strongly dependent on Build-Module doing the right thing
            Build-Module can optionally pass a PREFIX or SUFFIX, but otherwise only passes files

            Because of that, SetModuleContent doesn't test for that

            The goal here is to pretend this is a pipeline, for the sake of memory and file IO
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSReviewUnusedParameter", "OutputPath", Justification = "The rule is buggy")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSReviewUnusedParameter", "Encoding", Justification = "The rule is buggy ")]
    [CmdletBinding()]
    param(
        # Where to write the joined output
        [Parameter(Position=0, Mandatory)]
        [string]$OutputPath,

        # Input files, the scripts that will be copied to the output path
        # The FIRST and LAST items can be text content instead of file paths.
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias("PSPath", "FullName")]
        [AllowEmptyCollection()]
        [string[]]$SourceFile,

        # The working directory (allows relative paths for other values)
        [string]$WorkingDirectory = $pwd,

        # The encoding defaults to UTF8 (or UTF8NoBom on Core)
        [Parameter(DontShow)]
        [string]$Encoding = $(if($IsCoreCLR) { "UTF8Bom" } else { "UTF8" })
    )
    begin {
        Write-Debug "SetModuleContent WorkingDirectory $WorkingDirectory"
        Push-Location $WorkingDirectory -StackName SetModuleContent
        $ContentStarted = $false # There has been no content yet

        # Create a proxy command style scriptblock for Set-Content to keep the file handle open
        $SetContentCmd = $ExecutionContext.InvokeCommand.GetCommand('Microsoft.PowerShell.Management\Set-Content', [System.Management.Automation.CommandTypes]::Cmdlet)
        $SetContent = {& $SetContentCmd -Path $OutputPath -Encoding $Encoding}.GetSteppablePipeline($myInvocation.CommandOrigin)
        $SetContent.Begin($true)
    }
    process  {
        foreach($file in $SourceFile) {
            if($SourceName = Resolve-Path $file -Relative -ErrorAction SilentlyContinue) {
                Write-Verbose "Adding $SourceName"
                # Setting offset to -1 because of the new line we're adding.
                # This is needed for the code coverage calculation.
                $SetContent.Process("#Region '$SourceName' -1`n")
                Get-Content $SourceName -OutVariable source | ForEach-Object { $SetContent.Process($_) }
                $SetContent.Process("#EndRegion '$SourceName' $($Source.Count+1)")
            } else {
                if(!$ContentStarted) {
                    $SetContent.Process("#Region 'PREFIX' -1`n")
                    $SetContent.Process($file)
                    $SetContent.Process("#EndRegion 'PREFIX'")
                    $ContentStarted = $true
                } else {
                    $SetContent.Process("#Region 'SUFFIX' -1`n")
                    $SetContent.Process($file)
                    $SetContent.Process("#EndRegion 'SUFFIX'")
                }
            }
        }
    }
    end {
        $SetContent.End()
        Pop-Location -StackName SetModuleContent
    }
}
#EndRegion './Private/SetModuleContent.ps1' 73
#Region './Public/Build-Module.ps1' -1

function Build-Module {
    <#
        .Synopsis
            Compile a module from ps1 files to a single psm1

        .Description
            Compiles modules from source according to conventions:
            1. A single ModuleName.psd1 manifest file with metadata
            2. Source subfolders in the same directory as the Module manifest:
               Enum, Classes, Private, Public contain ps1 files
            3. Optionally, a build.psd1 file containing settings for this function

            The optimization process:
            1. The OutputDirectory is created
            2. All psd1/psm1/ps1xml files (except build.psd1) in the Source will be copied to the output
            3. If specified, $CopyPaths (relative to the Source) will be copied to the output
            4. The ModuleName.psm1 will be generated (overwritten completely) by concatenating all .ps1 files in the $SourceDirectories subdirectories
            5. The ModuleVersion and ExportedFunctions in the ModuleName.psd1 may be updated (depending on parameters)

        .Example
            Build-Module -Suffix "Export-ModuleMember -Function *-* -Variable PreferenceVariable"

            This example shows how to build a simple module from it's manifest, adding an Export-ModuleMember as a Suffix

        .Example
            Build-Module -Prefix "using namespace System.Management.Automation"

            This example shows how to build a simple module from it's manifest, adding a using statement at the top as a prefix

        .Example
            $gitVersion = gitversion | ConvertFrom-Json | Select -Expand InformationalVersion
            Build-Module -SemVer $gitVersion

            This example shows how to use a semantic version from gitversion to version your build.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "", Justification="Build is approved now")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseCmdletCorrectly", "")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSReviewUnusedParameter", "", Justification="Parameter handling is in InitializeBuild")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidDefaultValueSwitchParameter", "", Justification = "VersionedOutputDirectory is Deprecated")]
    [CmdletBinding(DefaultParameterSetName="SemanticVersion")]
    [Alias("build")]
    param(
        # The path to the module folder, manifest or build.psd1
        [Parameter(Position = 0, ValueFromPipelineByPropertyName)]
        [ValidateScript({
            if (Test-Path $_) {
                $true
            } else {
                throw "Source must point to a valid module"
            }
        })]
        [Alias("ModuleManifest", "Path")]
        [string]$SourcePath = $(Get-Location -PSProvider FileSystem),

        # Where to build the module. Defaults to "../Output" adjacent to the "SourcePath" folder.
        # The ACTUAL output may be in a subfolder of this path ending with the module name and version
        # The default value is ../Output which results in the build going to ../Output/ModuleName/1.2.3
        [Alias("Destination")]
        [string]$OutputDirectory = "../Output",

        # DEPRECATED. Now defaults true, producing a OutputDirectory with a version number as the last folder
        [switch]$VersionedOutputDirectory = $true,

        # Overrides the VersionedOutputDirectory, producing an OutputDirectory without a version number as the last folder
        [switch]$UnversionedOutputDirectory,

        # Semantic version, like 1.0.3-beta01+sha.22c35ffff166f34addc49a3b80e622b543199cc5
        # If the SemVer has metadata (after a +), then the full Semver will be added to the ReleaseNotes
        [Parameter(ParameterSetName="SemanticVersion")]
        [string]$SemVer,

        # The module version (must be a valid System.Version such as PowerShell supports for modules)
        [Alias("ModuleVersion")]
        [Parameter(ParameterSetName="ModuleVersion", Mandatory)]
        [version]$Version = $(if(($V = $SemVer.Split("+")[0].Split("-",2)[0])){$V}),

        # Setting pre-release forces the release to be a pre-release.
        # Must be valid pre-release tag like PowerShellGet supports
        [Parameter(ParameterSetName="ModuleVersion")]
        [string]$Prerelease = $($SemVer.Split("+")[0].Split("-",2)[1]),

        # Build metadata (like the commit sha or the date).
        # If a value is provided here, then the full Semantic version will be inserted to the release notes:
        # Like: ModuleName v(Version(-Prerelease?)+BuildMetadata)
        [Parameter(ParameterSetName="ModuleVersion")]
        [string]$BuildMetadata = $($SemVer.Split("+",2)[1]),

        # Folders which should be copied intact to the module output
        # Can be relative to the  module folder
        [AllowEmptyCollection()]
        [Alias("CopyDirectories")]
        [string[]]$CopyPaths = @(),

        # Folders which contain source .ps1 scripts to be concatenated into the module
        # Defaults to Enum, Classes, Private, Public
        [string[]]$SourceDirectories = @(
            "[Ee]num", "[Cc]lasses", "[Pp]rivate", "[Pp]ublic"
        ),

        # A Filter (relative to the module folder) for public functions
        # If non-empty, FunctionsToExport will be set with the file BaseNames of matching files
        # Defaults to Public/*.ps1
        [AllowEmptyString()]
        [string[]]$PublicFilter = "[Pp]ublic/*.ps1",

        # A switch that allows you to disable the update of the AliasesToExport
        # By default, (if PublicFilter is not empty, and this is not set)
        # Build-Module updates the module manifest FunctionsToExport and AliasesToExport
        # with the combination of all the values in [Alias()] attributes on public functions
        # and aliases created with `New-ALias` or `Set-Alias` at script level in the module
        [Alias("IgnoreAliasAttribute")]
        [switch]$IgnoreAlias,

        # File encoding for output RootModule (defaults to UTF8)
        # Converted to System.Text.Encoding for PowerShell 6 (and something else for PowerShell 5)
        [ValidateSet("UTF8", "UTF8Bom", "UTF8NoBom", "UTF7", "ASCII", "Unicode", "UTF32")]
        [string]$Encoding = $(if($IsCoreCLR) { "UTF8Bom" } else { "UTF8" }),

        # The prefix is either the path to a file (relative to the module folder) or text to put at the top of the file.
        # If the value of prefix resolves to a file, that file will be read in, otherwise, the value will be used.
        # The default is nothing. See examples for more details.
        [string]$Prefix,

        # The Suffix is either the path to a file (relative to the module folder) or text to put at the bottom of the file.
        # If the value of Suffix resolves to a file, that file will be read in, otherwise, the value will be used.
        # The default is nothing. See examples for more details.
        [Alias("ExportModuleMember","Postfix")]
        [string]$Suffix,

        # Controls whether we delete the output folder and whether we build the output
        # There are three options:
        #   - Clean deletes the build output folder
        #   - Build builds the module output
        #   - CleanBuild first deletes the build output folder and then builds the module back into it
        # Note that the folder to be deleted is the actual calculated output folder, with the version number
        # So for the default OutputDirectory with version 1.2.3, the path to clean is: ../Output/ModuleName/1.2.3
        [ValidateSet("Clean", "Build", "CleanBuild")]
        [string]$Target = "CleanBuild",

        # Output the ModuleInfo of the "built" module
        [switch]$Passthru
    )

    begin {
        if ($Encoding -notmatch "UTF8") {
            Write-Warning "For maximum portability, we strongly recommend you build your script modules with UTF8 encoding (with a BOM, for backwards compatibility to PowerShell 5)."
        }
    }
    process {
        try {
            # Push into the module source (it may be a subfolder)
            $ModuleInfo = InitializeBuild $SourcePath
            Write-Progress "Building $($ModuleInfo.Name)" -Status "Use -Verbose for more information"
            Write-Verbose  "Building $($ModuleInfo.Name)"

            # Ensure the OutputDirectory (exists for build, or is cleaned otherwise)
            $OutputDirectory = $ModuleInfo | ResolveOutputFolder
            if ($ModuleInfo.Target -notmatch "Build") {
                return
            }
            $RootModule = Join-Path $OutputDirectory "$($ModuleInfo.Name).psm1"
            $OutputManifest = Join-Path $OutputDirectory "$($ModuleInfo.Name).psd1"
            Write-Verbose  "Output to: $OutputDirectory"

            # Skip the build if it's up to date already
            Write-Verbose "Target $($ModuleInfo.Target)"
            $NewestBuild = (Get-Item $RootModule -ErrorAction SilentlyContinue).LastWriteTime
            $IsNew = Get-ChildItem $ModuleInfo.ModuleBase -Recurse |
                Where-Object LastWriteTime -gt $NewestBuild |
                Select-Object -First 1 -ExpandProperty LastWriteTime

            if ($null -eq $IsNew) {
                # This is mostly for testing ...
                if ($ModuleInfo.Passthru) {
                    Get-Module $OutputManifest -ListAvailable
                }
                return # Skip the build
            }

            # Note that the module manifest parent folder is the "root" of the source directories
            Push-Location $ModuleInfo.ModuleBase -StackName Build-Module

            Write-Verbose "Copy files to $OutputDirectory"
            # Copy the files and folders which won't be processed
            Copy-Item *.psm1, *.psd1, *.ps1xml -Exclude "build.psd1" -Destination $OutputDirectory -Force
            if ($ModuleInfo.CopyPaths) {
                Write-Verbose "Copy Entire Directories: $($ModuleInfo.CopyPaths)"
                Copy-Item -Path $ModuleInfo.CopyPaths -Recurse -Destination $OutputDirectory -Force
            }

            Write-Verbose "Combine scripts to $RootModule"

            # SilentlyContinue because there don't *HAVE* to be functions at all
            Write-Debug "  SourceDirectories: $($ModuleInfo.ModuleBase) + $($ModuleInfo.SourceDirectories -join '|')"
            $AllScripts = @($ModuleInfo.SourceDirectories).ForEach{
                # By explicitly converting, we support wildcards in the SourceDirectories parameter
                if ($SourceDirectory = Join-Path -Path $ModuleInfo.ModuleBase -ChildPath $_ | Convert-Path -ErrorAction SilentlyContinue) {
                    Write-Debug "  SourceDirectory: $SourceDirectory"
                    Get-ChildItem -Path $SourceDirectory -Filter *.ps1 -Recurse -ErrorAction SilentlyContinue |
                        Sort-Object -Property 'FullName'
                }
            }

            # We have to force the Encoding to string because PowerShell Core made up encodings
            SetModuleContent -Source (@($ModuleInfo.Prefix) + $AllScripts.FullName + @($ModuleInfo.Suffix)).Where{$_} -Output $RootModule -Encoding "$($ModuleInfo.Encoding)"

            $ParseResult = ConvertToAst $RootModule
            $ParseResult | MoveUsingStatements -Encoding "$($ModuleInfo.Encoding)"

            # If there is a PublicFilter, update ExportedFunctions
            if ($ModuleInfo.PublicFilter) {
                # SilentlyContinue because there don't *HAVE* to be public functions
                if (($PublicFunctions = Get-ChildItem $ModuleInfo.PublicFilter -Recurse -ErrorAction SilentlyContinue |
                        Where-Object BaseName -in $AllScripts.BaseName |
                        Select-Object -ExpandProperty BaseName)) {

                    Update-Metadata -Path $OutputManifest -PropertyName FunctionsToExport -Value $PublicFunctions
                }
            }

            # In order to support aliases to files, such as required by Invoke-Build, always export aliases
            if (-not $ModuleInfo.IgnoreAlias) {
                if (($AliasesToExport = $ParseResult | GetCommandAlias)) {
                    Update-Metadata -Path $OutputManifest -PropertyName AliasesToExport -Value $AliasesToExport
                }
            }

            try {
                if ($ModuleInfo.Version) {
                    Write-Verbose "Update Manifest at $OutputManifest with version: $($ModuleInfo.Version)"
                    Update-Metadata -Path $OutputManifest -PropertyName ModuleVersion -Value $ModuleInfo.Version
                }
            } catch {
                Write-Warning "Failed to update version to $($ModuleInfo.Version). $_"
            }

            if ($null -ne (Get-Metadata -Path $OutputManifest -PropertyName PrivateData.PSData.Prerelease -ErrorAction SilentlyContinue)) {
                if ($ModuleInfo.Prerelease) {
                    Write-Verbose "Update Manifest at $OutputManifest with Prerelease: $($ModuleInfo.Prerelease)"
                    Update-Metadata -Path $OutputManifest -PropertyName PrivateData.PSData.Prerelease -Value $ModuleInfo.Prerelease
                } elseif ($PSCmdlet.ParameterSetName -eq "SemanticVersion" -or $PSBoundParameters.ContainsKey("Prerelease")) {
                    Update-Metadata -Path $OutputManifest -PropertyName PrivateData.PSData.Prerelease -Value ""
                }
            } elseif ($ModuleInfo.Prerelease) {
                Write-Warning ("Cannot set Prerelease in module manifest. Add an empty Prerelease to your module manifest, like:`n" +
                               '         PrivateData = @{ PSData = @{ Prerelease = "" } }')
            }

            if ($ModuleInfo.BuildMetadata) {
                Write-Verbose "Update Manifest at $OutputManifest with metadata: $($ModuleInfo.BuildMetadata) from $($ModuleInfo.SemVer)"
                $RelNote = Get-Metadata -Path $OutputManifest -PropertyName PrivateData.PSData.ReleaseNotes -ErrorAction SilentlyContinue
                if ($null -ne $RelNote) {
                    $Line = "$($ModuleInfo.Name) v$($($ModuleInfo.SemVer))"
                    if ([string]::IsNullOrWhiteSpace($RelNote)) {
                        Write-Verbose "New ReleaseNotes:`n$Line"
                        Update-Metadata -Path $OutputManifest -PropertyName PrivateData.PSData.ReleaseNotes -Value $Line
                    } elseif ($RelNote -match "^\s*\n") {
                        # Leading whitespace includes newlines
                        Write-Verbose "Existing ReleaseNotes:$RelNote"
                        $RelNote = $RelNote -replace "^(?s)(\s*)\S.*$|^$","`${1}$($Line)`$_"
                        Write-Verbose "New ReleaseNotes:$RelNote"
                        Update-Metadata -Path $OutputManifest -PropertyName PrivateData.PSData.ReleaseNotes -Value $RelNote
                    } else {
                        Write-Verbose "Existing ReleaseNotes:`n$RelNote"
                        $RelNote = $RelNote -replace "^(?s)(\s*)\S.*$|^$","`${1}$($Line)`n`$_"
                        Write-Verbose "New ReleaseNotes:`n$RelNote"
                        Update-Metadata -Path $OutputManifest -PropertyName PrivateData.PSData.ReleaseNotes -Value $RelNote
                    }
                }
            }

            # This is mostly for testing ...
            if ($ModuleInfo.Passthru) {
                Get-Module $OutputManifest -ListAvailable
            }
        } finally {
            Pop-Location -StackName Build-Module -ErrorAction SilentlyContinue
        }
        Write-Progress "Building $($ModuleInfo.Name)" -Completed
    }
}
#EndRegion './Public/Build-Module.ps1' 282
#Region './Public/Convert-Breakpoint.ps1' -1

function Convert-Breakpoint {
    <#
        .SYNOPSIS
            Convert any breakpoints on source files to module files and vice-versa
    #>
    [CmdletBinding(DefaultParameterSetName="All")]
    param(
        [Parameter(ParameterSetName="Module")]
        [switch]$ModuleOnly,
        [Parameter(ParameterSetName="Source")]
        [switch]$SourceOnly
    )

    if (!$SourceOnly) {
        foreach ($ModuleBreakPoint in Get-PSBreakpoint | ConvertFrom-SourceLineNumber) {
            Set-PSBreakpoint -Script $ModuleBreakPoint.Script -Line $ModuleBreakPoint.Line
            if ($ModuleOnly) {
                # TODO: | Remove-PSBreakpoint
            }
        }
    }

    if (!$ModuleOnly) {
        foreach ($SourceBreakPoint in Get-PSBreakpoint | ConvertTo-SourceLineNumber) {
            if (!(Test-Path $SourceBreakPoint.SourceFile)) {
                Write-Warning "Can't find source path: $($SourceBreakPoint.SourceFile)"
            } else {
                Set-PSBreakpoint -Script $SourceBreakPoint.SourceFile -Line $SourceBreakPoint.SourceLineNumber
            }
            if ($SourceOnly) {
                # TODO: | Remove-PSBreakpoint
            }
        }
    }
}
#EndRegion './Public/Convert-Breakpoint.ps1' 36
#Region './Public/Convert-CodeCoverage.ps1' -1

function Convert-CodeCoverage {
    <#
        .SYNOPSIS
            Convert the file name and line numbers from Pester code coverage of "optimized" modules to the source
        .DESCRIPTION
            Converts the code coverage line numbers from Pester to the source file paths.
            The returned file name is always the relative path stored in the module.
        .EXAMPLE
            Invoke-Pester .\Tests -CodeCoverage (Get-ChildItem .\Output -Filter *.psm1).FullName -PassThru |
                Convert-CodeCoverage -SourceRoot .\Source -Relative

            Runs pester tests from a "Tests" subfolder against an optimized module in the "Output" folder,
            piping the results through Convert-CodeCoverage to render the code coverage misses with the source paths.
    #>
    param(
        # The root of the source folder (for resolving source code paths)
        [Parameter(Mandatory)]
        [string]$SourceRoot,

        # The output of `Invoke-Pester -Pasthru`
        # Note: Pester doesn't apply a custom type name
        [Parameter(ValueFromPipeline)]
        [PSObject]$InputObject
    )
    process {
        Push-Location $SourceRoot
        try {
            $InputObject.CodeCoverage.MissedCommands | ConvertTo-SourceLineNumber -Passthru |
                Select-Object SourceFile, @{Name="Line"; Expr={$_.SourceLineNumber}}, Command
        } finally {
            Pop-Location
        }
    }
}
#EndRegion './Public/Convert-CodeCoverage.ps1' 35
#Region './Public/ConvertFrom-SourceLineNumber.ps1' -1

function ConvertFrom-SourceLineNumber {
    <#
        .SYNOPSIS
            Convert a source file path and line number to the line number in the built output
        .EXAMPLE
            ConvertFrom-SourceLineNumber -Module ~\2.0.0\ModuleBuilder.psm1 -SourceFile ~\Source\Public\Build-Module.ps1 -Line 27
    #>
    [CmdletBinding(DefaultParameterSetName="FromString")]
    param(
        # The SourceFile is the source script file that was built into the module
        [Parameter(Mandatory, ValueFromPipelineByPropertyName, Position=0)]
        [Alias("PSCommandPath", "File", "ScriptName", "Script")]
        [string]$SourceFile,

        # The SourceLineNumber (from an InvocationInfo) is the line number in the source file
        [Parameter(Mandatory, ValueFromPipelineByPropertyName, Position=1)]
        [Alias("LineNumber", "Line", "ScriptLineNumber")]
        [int]$SourceLineNumber,

        # The name of the module in memory, or the full path to the module psm1
        [Parameter()]
        [string]$Module
    )
    begin {
        $filemap = @{}
    }
    process {
        if (!$Module) {
            $Command = [IO.Path]::GetFileNameWithoutExtension($SourceFile)
            $Module = (Get-Command $Command -ErrorAction SilentlyContinue).Source
            if (!$Module) {
                Write-Warning "Please specify -Module for ${SourceFile}: $SourceLineNumber"
                return
            }
        }
        if ($Module -and -not (Test-Path $Module)) {
            $Module = (Get-Module $Module -ErrorAction Stop).Path
        }
        # Push-Location (Split-Path $SourceFile)
        try {
            if (!$filemap.ContainsKey($Module)) {
                # Note: the new pattern is #Region but the old one was # BEGIN
                $regions = Select-String '^(?:#Region|# BEGIN) (?<SourceFile>.*) (?<LineNumber>-?\d+)?$' -Path $Module
                $filemap[$Module] = @($regions.ForEach{
                    [PSCustomObject]@{
                        PSTypeName = "BuildSourceMapping"
                        SourceFile = $_.Matches[0].Groups["SourceFile"].Value.Trim("'")
                        StartLineNumber = $_.LineNumber
                        # This offset is subtracted when calculating the line number
                        # because of the new line we're adding prior to the content
                        # of each script file in the built module.
                        Offset = $_.Matches[0].Groups["LineNumber"].Value
                    }
                })
            }

            $hit = $filemap[$Module]

            if ($Source = $hit.Where{ $SourceFile.EndsWith($_.SourceFile.TrimStart(".\")) }) {
                [PSCustomObject]@{
                    PSTypeName = "OutputLocation"
                    Script     = $Module
                    Line       = $Source.StartLineNumber + $SourceLineNumber - $Source.Offset
                }
            } elseif($Source -eq $Module) {
                [PSCustomObject]@{
                    PSTypeName = "OutputLocation"
                    Script     = $Module
                    Line       = $SourceLineNumber - $Source.Offset
                }
            } else {
                Write-Warning "'$SourceFile' not found in $Module"
            }
        } finally {
            Pop-Location
        }
    }
}
#EndRegion './Public/ConvertFrom-SourceLineNumber.ps1' 79
#Region './Public/ConvertTo-SourceLineNumber.ps1' -1

function ConvertTo-SourceLineNumber {
    <#
        .SYNOPSIS
            Convert the line number in a built module to a file and line number in source
        .EXAMPLE
            ConvertTo-SourceLineNumber -SourceFile ~\ErrorMaker.psm1 -SourceLineNumber 27
        .EXAMPLE
            ConvertTo-SourceLineNumber -PositionMessage "At C:\Users\Joel\OneDrive\Documents\PowerShell\Modules\ErrorMaker\ErrorMaker.psm1:27 char:4"
    #>
    [Alias("Convert-LineNumber")]
    [CmdletBinding(DefaultParameterSetName="FromString")]
    param(
        # A position message as found in PowerShell's error messages, ScriptStackTrace, or InvocationInfo
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName="FromString")]
        [string]$PositionMessage,

        # The SourceFile (from an InvocationInfo) is the module psm1 path
        [Parameter(Mandatory, ValueFromPipelineByPropertyName, Position=0, ParameterSetName="FromInvocationInfo")]
        [Alias("PSCommandPath", "File", "ScriptName", "Script")]
        [string]$SourceFile,

        # The SourceLineNumber (from an InvocationInfo) is the module line number
        [Parameter(Mandatory, ValueFromPipelineByPropertyName, Position=1, ParameterSetName="FromInvocationInfo")]
        [Alias("LineNumber", "Line", "ScriptLineNumber")]
        [int]$SourceLineNumber,

        # The actual InvocationInfo
        [Parameter(ValueFromPipeline, DontShow, ParameterSetName="FromInvocationInfo")]
        [psobject]$InputObject,

        # If set, passes through the InputObject, overwriting the SourceFile and SourceLineNumber.
        # Otherwise, creates a new SourceLocation object with just those properties.
        [Parameter(ParameterSetName="FromInvocationInfo")]
        [switch]$Passthru
    )
    begin {
        $filemap = @{}
    }
    process {
        if ($PSCmdlet.ParameterSetName -eq "FromString") {
            $Invocation = ParseLineNumber $PositionMessage
            $SourceFile = $Invocation.SourceFile
            $SourceLineNumber = $Invocation.SourceLineNumber
        }
        if (!(Test-Path $SourceFile)) {
            throw "'$SourceFile' does not exist"
        }
        Push-Location (Split-Path $SourceFile)
        try {
            if (!$filemap.ContainsKey($SourceFile)) {
                # Note: the new pattern is #Region but the old one was # BEGIN
                $regions = Select-String '^(?:#Region|# BEGIN) (?<SourceFile>.*) (?<LineNumber>-?\d+)?$' -Path $SourceFile
                if ($regions.Count -eq 0) {
                    Write-Warning "No SourceMap for $SourceFile"
                    return
                }
                $filemap[$SourceFile] = @($regions.ForEach{
                        [PSCustomObject]@{
                            PSTypeName = "BuildSourceMapping"
                            SourceFile = $_.Matches[0].Groups["SourceFile"].Value.Trim("'")
                            StartLineNumber = [System.Int32] $_.LineNumber
                            # This offset is added when calculating the line number
                            # because of the new line we're adding prior to the content
                            # of each script file in the built module.
                            Offset = $_.Matches[0].Groups["LineNumber"].Value
                        }
                    })
            }

            $hit = $filemap[$SourceFile]

            # These are all negative, because BinarySearch returns the match *after* the line we're searching for
            # We need the match *before* the line we're searching for
            # And we need it as a zero-based index:
            $index = -2 - [Array]::BinarySearch($hit.StartLineNumber, $SourceLineNumber)
            $Source = $hit[$index]

            if($Passthru) {
                $InputObject |
                    Add-Member -MemberType NoteProperty -Name SourceFile -Value $Source.SourceFile -PassThru -Force |
                    Add-Member -MemberType NoteProperty -Name SourceLineNumber -Value ($SourceLineNumber - $Source.StartLineNumber + $Source.Offset) -PassThru -Force
            } else {
                [PSCustomObject]@{
                    PSTypeName = "SourceLocation"
                    SourceFile = $Source.SourceFile
                    SourceLineNumber = $SourceLineNumber - $Source.StartLineNumber + $Source.Offset
                }
            }
        } finally {
            Pop-Location
        }
    }
}
#EndRegion './Public/ConvertTo-SourceLineNumber.ps1' 94
