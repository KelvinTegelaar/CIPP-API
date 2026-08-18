function Get-CippGraphSchema {
    <#
    .SYNOPSIS
        Describes what a Microsoft Graph endpoint returns, without calling it.
    .DESCRIPTION
        Resolves a Graph path against the vendored CSDL ($metadata) and returns the entity
        type behind it with its properties and their types.

        The point is to answer "would this call even contain the field I need?" before
        spending a request on it - a Graph call against a real tenant is slow, is rate
        limited, and for AllTenants work is multiplied by the tenant count. Graph publishes
        the answer statically, so guessing at it is unnecessary.

        The CSDL is vendored under Config/graph-metadata (refresh with
        build/tools/vendor-graph-metadata.ps1), so this never makes a network call of its
        own. The parsed index is cached per worker runspace.

        Property types are the OData/EDM names mapped onto JSON types. A property whose
        type is another Graph type is reported as that type name, so a caller can follow it.
    .EXAMPLE
        Get-CippGraphSchema -Endpoint 'users'
        Get-CippGraphSchema -Endpoint 'groups/{id}/members' -Version v1.0
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        # A Graph path: 'users', 'users/{id}/manager', or a full https://graph.microsoft.com URL.
        [Parameter(Mandatory)][string]$Endpoint,
        [ValidateSet('v1.0', 'beta')][string]$Version = 'beta',
        [switch]$Force
    )

    $Index = Get-CippGraphSchemaIndex -Version $Version -Force:$Force

    # Accept a full URL, a leading slash, a version prefix, and any query string.
    $Path = $Endpoint -replace '^https?://[^/]+/', ''
    $Path = $Path -replace '^(v1\.0|beta)/', ''
    $Path = ($Path -split '\?')[0]
    $Path = $Path.Trim('/')

    $Segments = @($Path -split '/' | Where-Object { $_ })
    if ($Segments.Count -eq 0) { throw 'Endpoint is required, e.g. "users".' }

    # Key predicates and template placeholders address one item; they do not change the type.
    $Meaningful = foreach ($Segment in $Segments) {
        $Clean = ($Segment -split '\(')[0]
        if ($Clean -match '^\{.*\}$' -or $Clean -match '^\$') { continue }
        # a literal id sitting in the path, e.g. users/48d31887-.../manager
        if ($Clean -match '^[0-9a-fA-F-]{36}$' -or $Clean -match '@') { continue }
        $Clean
    }
    $Meaningful = @($Meaningful | Where-Object { $_ })
    if ($Meaningful.Count -eq 0) { throw "Could not read an entity set from '$Endpoint'." }

    # The first segment names an entity set or singleton; each later one is a navigation
    # property on the type reached so far.
    $Root = $Meaningful[0]
    $TypeName = $Index.Sets[$Root]
    if (-not $TypeName) {
        throw "'$Root' is not a known Graph entity set in $Version. Check the spelling, or try the other API version."
    }

    $Traversed = [System.Collections.Generic.List[string]]::new()
    $Traversed.Add($Root)

    for ($i = 1; $i -lt $Meaningful.Count; $i++) {
        $Type = $Index.Types[$TypeName]
        if (-not $Type) { break }
        $Next = $Type.Navigation[$Meaningful[$i]]
        if (-not $Next) {
            throw "'$($Meaningful[$i])' is not a navigation property on $TypeName. Available: $((@($Type.Navigation.Keys) | Sort-Object) -join ', ')"
        }
        $TypeName = $Next
        $Traversed.Add($Meaningful[$i])
    }

    $Resolved = $Index.Types[$TypeName]
    if (-not $Resolved) { throw "Resolved to type '$TypeName', which is not defined in the $Version metadata." }

    return [ordered]@{
        endpoint   = $Path
        version    = $Version
        # fully qualified, because several namespaces declare a type of the same short name
        entityType = $TypeName
        path       = ($Traversed -join '/')
        properties = [ordered]@{} + $Resolved.Properties
        navigation = [ordered]@{} + $Resolved.Navigation
        note       = 'Derived from the vendored Graph CSDL, not from a live call. Graph only returns a subset by default; request the fields you need with $select.'
    }
}

function Get-CippGraphSchemaIndex {
    <#
    .SYNOPSIS
        Parses the vendored Graph CSDL into a lookup of entity sets and types.
    .DESCRIPTION
        Flattens BaseType inheritance so a caller sees every property an entity actually
        carries: microsoft.graph.user declares 87 of its own and inherits the rest from
        directoryObject, and a caller asking "does user have an id" should not have to know
        that. Cached per worker runspace because the beta document is ~7 MB of XML.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([ValidateSet('v1.0', 'beta')][string]$Version = 'beta', [switch]$Force)

    if (-not $script:CippGraphSchemaIndex) { $script:CippGraphSchemaIndex = @{} }
    if ($script:CippGraphSchemaIndex[$Version] -and -not $Force) { return $script:CippGraphSchemaIndex[$Version] }

    $Path = Join-Path -Path $env:CIPPRootPath -ChildPath "Config/graph-metadata/$Version.xml"
    if (-not (Test-Path $Path)) {
        throw "Graph metadata for $Version is not vendored at $Path. Run build/tools/vendor-graph-metadata.ps1."
    }

    $EdmToJson = @{
        'Edm.String' = 'string'; 'Edm.Boolean' = 'boolean'; 'Edm.Int16' = 'integer'
        'Edm.Int32' = 'integer'; 'Edm.Int64' = 'integer'; 'Edm.Double' = 'number'
        'Edm.Single' = 'number'; 'Edm.Decimal' = 'number'; 'Edm.Guid' = 'string'
        'Edm.DateTimeOffset' = 'string (date-time)'; 'Edm.Date' = 'string (date)'
        'Edm.TimeOfDay' = 'string (time)'; 'Edm.Duration' = 'string (duration)'
        'Edm.Binary' = 'string (base64)'; 'Edm.Stream' = 'string (stream)'
    }

    function Convert-EdmType {
        param([string]$Type)
        if (-not $Type) { return 'unknown' }
        $IsCollection = $Type -match '^Collection\((.+)\)$'
        $Inner = if ($IsCollection) { $Matches[1] } else { $Type }
        $Mapped = if ($EdmToJson.ContainsKey($Inner)) { $EdmToJson[$Inner] } else { ($Inner -split '\.')[-1] }
        if ($IsCollection) { return "$Mapped[]" }
        return $Mapped
    }

    $Xml = [System.Xml.XmlDocument]::new()
    $Xml.PreserveWhitespace = $false
    $Xml.Load($Path)

    $Namespace = [System.Xml.XmlNamespaceManager]::new($Xml.NameTable)
    $Namespace.AddNamespace('edm', 'http://docs.oasis-open.org/odata/ns/edm')

    # Types MUST be keyed by their fully qualified name. The beta document declares several
    # different types called 'user' in different namespaces - the directory user, and a
    # handful of usage-report users - so keying on the short name lets a report type
    # silently overwrite microsoft.graph.user, and 'users' then resolves to a 10-property
    # object with no id on it.
    #
    # Each Schema also declares an Alias, and references use the two interchangeably
    # ('graph.user' and 'microsoft.graph.user' are the same type), so aliases are expanded
    # before any lookup.
    $AliasOf = @{}
    foreach ($Schema in $Xml.SelectNodes('//edm:Schema', $Namespace)) {
        if ($Schema.Alias) { $AliasOf[$Schema.Alias] = $Schema.Namespace }
    }

    function Expand-TypeName {
        param([string]$Type)
        if (-not $Type) { return $null }
        $Bare = $Type -replace '^Collection\(', '' -replace '\)$', ''
        $Prefix = $Bare -replace '\.[^.]+$', ''
        $Leaf = ($Bare -split '\.')[-1]
        if ($AliasOf.ContainsKey($Prefix)) { return '{0}.{1}' -f $AliasOf[$Prefix], $Leaf }
        return $Bare
    }

    $Raw = @{}
    foreach ($Schema in $Xml.SelectNodes('//edm:Schema', $Namespace)) {
        $SchemaNamespace = $Schema.Namespace
        foreach ($Node in $Schema.SelectNodes('edm:EntityType | edm:ComplexType', $Namespace)) {
            $Properties = [ordered]@{}
            $Navigation = [ordered]@{}
            foreach ($Property in $Node.SelectNodes('edm:Property', $Namespace)) {
                $Properties[$Property.Name] = Convert-EdmType -Type $Property.Type
            }
            foreach ($Property in $Node.SelectNodes('edm:NavigationProperty', $Namespace)) {
                $Navigation[$Property.Name] = Expand-TypeName -Type $Property.Type
            }
            $Raw['{0}.{1}' -f $SchemaNamespace, $Node.Name] = @{
                Properties = $Properties
                Navigation = $Navigation
                Base       = Expand-TypeName -Type $Node.BaseType
            }
        }
    }

    # Flatten inheritance, base first so a derived type can override.
    $Types = @{}
    function Resolve-Type {
        param([string]$Name, [System.Collections.Generic.HashSet[string]]$Seen)
        if ($Types.ContainsKey($Name)) { return $Types[$Name] }
        if (-not $Raw.ContainsKey($Name) -or $Seen.Contains($Name)) { return $null }
        $null = $Seen.Add($Name)

        $Properties = [ordered]@{}
        $Navigation = [ordered]@{}
        if ($Raw[$Name].Base) {
            $Parent = Resolve-Type -Name $Raw[$Name].Base -Seen $Seen
            if ($Parent) {
                foreach ($Key in $Parent.Properties.Keys) { $Properties[$Key] = $Parent.Properties[$Key] }
                foreach ($Key in $Parent.Navigation.Keys) { $Navigation[$Key] = $Parent.Navigation[$Key] }
            }
        }
        foreach ($Key in $Raw[$Name].Properties.Keys) { $Properties[$Key] = $Raw[$Name].Properties[$Key] }
        foreach ($Key in $Raw[$Name].Navigation.Keys) { $Navigation[$Key] = $Raw[$Name].Navigation[$Key] }

        $Types[$Name] = @{ Properties = $Properties; Navigation = $Navigation }
        return $Types[$Name]
    }
    foreach ($Name in $Raw.Keys) { $null = Resolve-Type -Name $Name -Seen ([System.Collections.Generic.HashSet[string]]::new()) }

    # Entity sets and singletons are the addressable roots. Case-insensitive because CIPP
    # writes 'serviceprincipals' in places where Graph declares 'servicePrincipals'.
    $Sets = [System.Collections.Hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Node in $Xml.SelectNodes('//edm:EntityContainer/edm:EntitySet | //edm:EntityContainer/edm:Singleton', $Namespace)) {
        $Type = if ($Node.EntityType) { $Node.EntityType } else { $Node.Type }
        $Sets[$Node.Name] = Expand-TypeName -Type $Type
    }

    $script:CippGraphSchemaIndex[$Version] = @{ Sets = $Sets; Types = $Types }
    return $script:CippGraphSchemaIndex[$Version]
}
