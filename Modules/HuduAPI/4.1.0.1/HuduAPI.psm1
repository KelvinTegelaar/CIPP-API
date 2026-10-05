#Region '.\Private\ArgumentCompleters\AssetLayoutCompleter.ps1' -1

$AssetLayoutCompleter = {
    param (
        $CommandName,
        $ParamName,
        $AssetLayout,
        $CommandAst,
        $fakeBoundParameters
    )
    if (!$script:AssetLayouts) {
        Get-HuduAssetLayouts | Out-Null
    }

    $AssetLayout = $AssetLayout -replace "'", ''
    ($script:AssetLayouts).name | Where-Object { $_ -match "$AssetLayout" } | ForEach-Object { "'$_'" }
}

Register-ArgumentCompleter -CommandName Get-HuduAssets -ParameterName AssetLayout -ScriptBlock $AssetLayoutCompleter
#EndRegion '.\Private\ArgumentCompleters\AssetLayoutCompleter.ps1' 18
#Region '.\Private\Assert-AllowedObjectType.ps1' -1

function Assert-AllowedObjectType {
    param(
        [Parameter(Mandatory)][string]$InputType,
        [Parameter(Mandatory)][string[]]$AllowedCanonicals
    )

    $canonical = Get-ObjectTypeFromCononical $InputType  # accepts aliases; throws if unknown

    if ($canonical -notin $AllowedCanonicals) {
        throw "Invalid type '$InputType' (canonical: '$canonical'). Allowed: $($AllowedCanonicals -join ', ')"
    }

    $true
}
#EndRegion '.\Private\Assert-AllowedObjectType.ps1' 15
#Region '.\Private\Convert-ToHuduDateRange.ps1' -1

function Convert-ToHuduDateRange {
    param(
        [Parameter(Position = 0)][Nullable[datetime]]$Start,
        [Parameter(Position = 1)][Nullable[datetime]]$End
    )

    $startStr = if ($Start) { $Start.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") } else { '' }
    $endStr = if ($End) { $End.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") } else { '' }

    return $(if (("$startStr,$endStr") -eq ",") {$null} else {"$startStr,$endStr"})
}
#EndRegion '.\Private\Convert-ToHuduDateRange.ps1' 12
#Region '.\Private\ConvertTo-HuduLabelColor.ps1' -1

function ConvertTo-HuduLabelColor {
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Color
    )

    $normalizedColor = $Color.Trim()

    if ($normalizedColor -match '^#?[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$') {
        $hexColor = $normalizedColor.TrimStart('#')
        return "#$($hexColor.Substring(0, 6))"
    }

    $canonicalColor = Set-ColorFromCanonical -inputData $normalizedColor
    $canonicalColorHex = @{
        Red         = '#ff0000'
        Blue        = '#0000ff'
        Green       = '#008000'
        Yellow      = '#ffff00'
        Purple      = '#800080'
        Orange      = '#ffa500'
        LightPink   = '#ffb6c1'
        LightBlue   = '#add8e6'
        LightGreen  = '#90ee90'
        LightPurple = '#cbc3e3'
        LightOrange = '#ffcc99'
        LightYellow = '#ffffe0'
        White       = '#ffffff'
        Grey        = '#808080'
    }

    if ($canonicalColorHex.ContainsKey($canonicalColor)) {
        return $canonicalColorHex[$canonicalColor]
    }

    throw "Invalid label color '$Color'. Unable to convert canonical color '$canonicalColor' to a hexadecimal color."
}
#EndRegion '.\Private\ConvertTo-HuduLabelColor.ps1' 39
#Region '.\Private\Get-AllowedTypeAliases.ps1' -1

function Get-AllowedTypeAliases {
    param(
        [Parameter(Mandatory)]
        [string[]]$AllowedTypes,
        [bool]$IncludeCanonical=$true
    )
    $first = $AllowedTypes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1
    if ($first) { [void](Get-ObjectTypeFromCononical $first) }

    $canonicals = $(foreach ($t in $AllowedTypes) {
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        Get-ObjectTypeFromCononical $t
    }) | Select-Object -Unique

    $vals = foreach ($c in $canonicals) {
        if ($IncludeCanonical) { $c }
        foreach ($a in $script:FlaggableTypeMap[$c]) { $a }
    }

    $vals |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.Trim() } |
        Select-Object -Unique
}
#EndRegion '.\Private\Get-AllowedTypeAliases.ps1' 25
#Region '.\Private\Get-HuduCompanyFolders.ps1' -1

function Get-HuduCompanyFolders {
    [CmdletBinding()]
    Param (
        [PSCustomObject]$FoldersRaw
    )

    $RootFolders = $FoldersRaw | Where-Object { $null -eq $_.parent_folder_id }
    $ReturnObject = [PSCustomObject]@{}
    foreach ($folder in $RootFolders) {
        $SubFolders = Get-HuduSubFolders -id $folder.id -FoldersRaw $FoldersRaw
        foreach ($SubFolder in $SubFolders) {
            $Folder | Add-Member -MemberType NoteProperty -Name $(Get-HuduFolderCleanName $($SubFolder.PSObject.Properties.name)) -Value $SubFolder.PSObject.Properties.value
        }
        $ReturnObject | Add-Member -MemberType NoteProperty -Name $(Get-HuduFolderCleanName $($folder.name)) -Value $folder
    }
    return $ReturnObject
}
#EndRegion '.\Private\Get-HuduCompanyFolders.ps1' 18
#Region '.\Private\Get-HuduFolderCleanName.ps1' -1

function Get-HuduFolderCleanName {
    [CmdletBinding()]
    param(
        [string]$Name
    )

    $FieldNames = @('id', 'company_id', 'icon', 'description', 'name', 'parent_folder_id', 'created_at', 'updated_at')

    if ($Name -in $FieldNames) {
        Return "fld_$Name"
    } else {
        Return $Name
    }

}
#EndRegion '.\Private\Get-HuduFolderCleanName.ps1' 16
#Region '.\Private\Get-HuduProcedureContext.ps1' -1

function Get-HuduProcedureContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$ProcedureId
    )

    $procedure = Get-HuduProcedures -Id $ProcedureId
    if (-not $procedure) {
        return $null
    }

    $isRun = $procedure.run -eq $true

    $processType = [string]$procedure.process_type
    $companyIdPresent = -not [string]::IsNullOrWhiteSpace([string]$procedure.company_id)

    $isGlobal = (
        $processType -ieq 'global' -or
        (-not $companyIdPresent -and -not $isRun)
    )

    $isCompanyProcess = (
        -not $isRun -and (
            $processType -ieq 'company' -or
            $companyIdPresent
        )
    )

    $canKickoff = $isCompanyProcess

    [pscustomobject]@{
        Procedure      = $procedure
        IsRun          = $isRun
        IsGlobal       = $isGlobal
        IsCompany      = $isCompanyProcess
        ProcessType    = $processType
        CompanyId      = if ($companyIdPresent) { [int]$procedure.company_id } else { $null }
        CanKickoff     = $canKickoff
    }
}
#EndRegion '.\Private\Get-HuduProcedureContext.ps1' 42
#Region '.\Private\Get-HuduSubFolders.ps1' -1

function Get-HuduSubFolders {
    [CmdletBinding()]
    Param(
        [int]$id,
        [PSCustomObject]$FoldersRaw
    )

    $SubFolders = $FoldersRaw | Where-Object { $_.parent_folder_id -eq $id }
    $ReturnFolders = [System.Collections.ArrayList]@()
    foreach ($Folder in $SubFolders) {
        $SubSubFolders = Get-HuduSubFolders -id $Folder.id -FoldersRaw $FoldersRaw
        foreach ($AddFolder in $SubSubFolders) {
            $null = $folder | Add-Member -MemberType NoteProperty -Name $(Get-HuduFolderCleanName $($AddFolder.PSObject.Properties.name)) -Value $AddFolder.PSObject.Properties.value
        }
        $ReturnObject = [PSCustomObject]@{
            $(Get-HuduFolderCleanName $($Folder.name)) = $Folder
        }
        $null = $ReturnFolders.add($ReturnObject)
    }

    return $ReturnFolders

}
#EndRegion '.\Private\Get-HuduSubFolders.ps1' 24
#Region '.\Private\Get-ObjectTypeFromCononical.ps1' -1

function Get-ObjectTypeFromCononical {
    param ([string]$inputData)
    if ([string]::IsNullOrWhiteSpace($inputData)) { return $null }

        if (-not $(get-variable -name 'script:ObjectTypeLookup' -scope 'script' -erroraction silentlycontinue)) {
            $script:ObjectTypeMap = [ordered]@{
                # English, German, French, Italian, Spanish, Portuguese, Dutch, Polish
                Article = @('article','articles','kb','kbs','knowledgebase','knowledgebases','knowledge_base','knowledge_bases','knowledgearticle','knowledgearticles','knowledge_article','knowledge_articles','artikel','wissensartikel','wissensdatenbank','wissensdatenbanken','base_de_connaissances','bases_de_connaissances','article_de_connaissance','articles_de_connaissance','articolo','articoli','base_di_conoscenza','basi_di_conoscenza','articolo_di_conoscenza','articoli_di_conoscenza','artículo','artículos','articulo','articulos','base_de_conocimiento','bases_de_conocimiento','artículo_de_conocimiento','artículos_de_conocimiento','articulo_de_conocimiento','articulos_de_conocimiento','artigo','artigos','base_de_conhecimento','bases_de_conhecimento','artigo_de_conhecimento','artigos_de_conhecimento','artikelen','kennisbank','kennisbanken','kennisartikel','kennisartikelen','artykuł','artykuły','artykul','artykuly','baza_wiedzy','bazy_wiedzy','artykuł_bazy_wiedzy','artykuły_bazy_wiedzy','artykul_bazy_wiedzy','artykuly_bazy_wiedzy')
                Asset = @('asset','assets','device','devices','equipment','hardware','anlage','anlagen','objekt','objekte','gerät','geräte','geraet','geraete','ausrüstung','ausruestung','actif','actifs','équipement','équipements','equipement','equipements','matériel','matériels','materiel','materiels','bene','beni','risorsa','risorse','dispositivo','dispositivi','apparecchiatura','apparecchiature','activo','activos','recurso','recursos','dispositivos','equipo','equipos','ativo','ativos','equipamento','equipamentos','bedrijfsmiddel','bedrijfsmiddelen','apparaat','apparaten','toestel','toestellen','apparatuur','zasób','zasoby','zasob','urządzenie','urządzenia','urzadzenie','urzadzenia','sprzęt','sprzet')
                AssetPassword = @('assetpassword','assetpasswords','asset_password','asset_passwords','password','passwords','credential','credentials','assetcredential','assetcredentials','asset_credential','asset_credentials','assetpasswort','assetpasswörter','assetpasswoerter','passwort','passwörter','passwoerter','kennwort','kennwörter','kennwoerter','zugangsdaten','motdepasse','motsdepasse','mot_de_passe','mots_de_passe','mot_de_passe_actif','mots_de_passe_actif','password_asset','password_risorsa','credenziale','credenziali','contraseña','contraseñas','contrasena','contrasenas','clave','claves','credencial','credenciales','contraseña_de_activo','contraseñas_de_activo','contrasena_de_activo','contrasenas_de_activo','senha','senhas','palavra_passe','palavras_passe','credenciais','senha_de_ativo','senhas_de_ativo','wachtwoord','wachtwoorden','assetwachtwoord','assetwachtwoorden','inloggegevens','hasło','hasła','haslo','hasla','hasło_zasobu','hasła_zasobu','haslo_zasobu','hasla_zasobu','dane_logowania')
                Company = @('company','companies','organization','organizations','organisation','organisations','org','orgs','business','businesses','client','clients','customer','customers','firma','firmen','unternehmen','organisationen','gesellschaft','gesellschaften','kunde','kunden','entreprise','entreprises','société','sociétés','societe','societes','compagnie','compagnies','azienda','aziende','impresa','imprese','società','societa','organizzazione','organizzazioni','cliente','clienti','empresa','empresas','compañía','compañías','compania','companias','organización','organizaciones','organizacion','sociedad','sociedades','clientes','companhia','companhias','organização','organizações','organizacao','organizacoes','sociedade','bedrijf','bedrijven','onderneming','ondernemingen','organisatie','organisaties',"firma's",'klant','klanten','firmy','przedsiębiorstwo','przedsiębiorstwa','przedsiebiorstwo','przedsiebiorstwa','organizacja','organizacje','spółka','spółki','spolka','spolki','klient','klienci')
                IpAddress = @('ipaddress','ipaddresses','ip_address','ip_addresses','ip','ips','ipaddr','ipaddrs','ipam','ipadresse','ipadressen','ip_adresse','ip_adressen','adresseip','adressesip','adresse_ip','adresses_ip','indirizzoip','indirizziip','indirizzo_ip','indirizzi_ip','direccionip','direccionesip','direccion_ip','direcciones_ip','dirección_ip','enderecoip','enderecosip','endereco_ip','enderecos_ip','endereço_ip','endereços_ip','ipadres','ip_adres','adres_ip','adresy_ip','adresip','adresyip')
                Network = @('network','networks','lan','lans', 'netzwerk','netzwerke','netz','netze', 'réseau','réseaux','reseau','reseaux', 'rete','reti', 'red','redes', 'rede', 'netwerk','netwerken')
                Photo = @('photo','photos','photograph','photographs','image','images','picture','pictures','foto','fotos','fotografie','fotografien','bild','bilder','photographie','photographies','immagine','immagini','fotografía','fotografías','fotografia','fotografias','imagen','imágenes','imagenes','imagem','imagens',"foto's",'afbeelding','afbeeldingen','beeld','beelden','zdjęcie','zdjęcia','zdjecie','zdjecia','obraz','obrazy')
                PublicPhoto = @('publicphoto','publicphotos','public_photo','public_photos','publicphotograph','publicphotographs','public_photograph','public_photographs','publicimage','publicimages','public_image','public_images','publicpicture','publicpictures','publicfoto','öffentliches_foto','öffentliche_fotos','oeffentliches_foto','oeffentliche_fotos','öffentliches_bild','öffentliche_bilder','oeffentliches_bild','oeffentliche_bilder','publicphotographie','photo_publique','photos_publiques','photographie_publique','photographies_publiques','image_publique','images_publiques','foto_pubblica','foto_pubbliche','fotografia_pubblica','fotografie_pubbliche','immagine_pubblica','immagini_pubbliche','publicfotografía','publicfotografia','foto_pública','fotos_públicas','foto_publica','fotos_publicas','fotografía_pública','fotografías_públicas','fotografia_publica','fotografias_publicas','imagen_pública','imágenes_públicas','imagen_publica','imagenes_publicas','imagem_pública','imagens_públicas','imagem_publica','imagens_publicas','openbare_foto',"openbare_foto's",'publieke_foto',"publieke_foto's",'openbare_afbeelding','openbare_afbeeldingen','publiczne_zdjęcie','publiczne_zdjęcia','publiczne_zdjecie','publiczne_zdjecia','publiczna_fotografia','publiczne_fotografie')
                Procedure = @('procedure','procedures','process','processes','checklist','checklists','tasklist','tasklists','task_list','task_lists','workflow','workflows','runbook','runbooks','sop','sops','standard_operating_procedure','standard_operating_procedures','verfahren','prozedur','prozeduren','prozess','prozesse','checkliste','checklisten','arbeitsanweisung','arbeitsanweisungen','ablauf','abläufe','ablaeufe','procédure','procédures','processus','liste_de_contrôle','listes_de_contrôle','liste_de_controle','listes_de_controle','mode_opératoire','modes_opératoires','mode_operatoire','modes_operatoires','flux_de_travail','procedura','processo','processi','lista_di_controllo','liste_di_controllo','flusso_di_lavoro','flussi_di_lavoro','istruzione','istruzioni','procedimiento','procedimientos','proceso','procesos','lista_de_verificación','listas_de_verificación','lista_de_verificacion','listas_de_verificacion','lista_de_comprobación','listas_de_comprobación','lista_de_comprobacion','listas_de_comprobacion','flujo_de_trabajo','flujos_de_trabajo','procedimento','procedimentos','processos','lista_de_verificação','listas_de_verificação','lista_de_verificacao','listas_de_verificacao','fluxo_de_trabalho','fluxos_de_trabalho','instrução','instruções','instrucao','instrucoes','proces','processen','werkinstructie','werkinstructies','werkproces','werkprocessen','procedury','procesy','lista_kontrolna','listy_kontrolne','instrukcja','instrukcje','przepływ_pracy','przeplyw_pracy')
                RackStorage = @('rackstorage','rackstorages','rack_storage','rack_storages','rack','racks','serverrack','serverracks','server_rack','server_racks','cabinet','cabinets','servercabinet','servercabinets','server_cabinet','server_cabinets','serverschrank','serverschränke','serverschraenke','schrank','schränke','schraenke','baie','baies','baie_informatique','baies_informatiques','armoire','armoires','armoire_informatique','armoires_informatiques','armadio','armadi','armadio_rack','armadi_rack','armadio_server','armadi_server','gabinete','gabinetes','armario','armarios','rack_de_servidor','racks_de_servidor','rack_de_servidores','racks_de_servidores','armário','armários','kast','kasten','serverkast','serverkasten','szafa','szafy','szafa_rackowa','szafy_rackowe','szafa_serwerowa','szafy_serwerowe')
                Vlan = @('vlan','vlans','virtual_lan','virtual_lans','virtual_local_area_network','virtual_local_area_networks','virtuelles_lan','virtuelle_lans','réseau_local_virtuel','réseaux_locaux_virtuels','reseau_local_virtuel','reseaux_locaux_virtuels','rete_locale_virtuale','reti_locali_virtuali','red_local_virtual','redes_locales_virtuales','rede_local_virtual','redes_locais_virtuais','virtueel_lan','virtuele_lans','wirtualna_sieć_lokalna','wirtualne_sieci_lokalne','wirtualna_siec_lokalna')
                VlanZone = @('vlanzone','vlanzones','vlan_zone','vlan_zones','zone','zones','network_zone','network_zones','vlan_zonen','zonen','netzwerkzone','netzwerkzonen','zone_vlan','zones_vlan','zone_réseau','zones_réseau','zone_reseau','zones_reseau','zona_vlan','zona','zona_di_rete','zone_di_rete','zonas_vlan','zonas','zona_de_red','zonas_de_red','zona_de_rede','zonas_de_rede','netwerkzone','netwerkzones','strefa_vlan','strefy_vlan','strefa','strefy','strefa_sieci','strefy_sieci')
                Website = @('website','websites','web_site','web_sites','site','sites','webpage','webpages','web_page','web_pages','internet_site','internet_sites','webseite','webseiten','internetseite','internetseiten','webauftritt','webauftritte','site_web','sites_web','site_internet','sites_internet','page_web','pages_web','sito','siti','sito_web','siti_web','sito_internet','siti_internet','pagina_web','pagine_web','sitio','sitios','sitio_web','sitios_web','sitio_internet','sitios_internet','página_web','páginas_web','paginas_web','sítio','sítios','sítio_web','sítios_web','webpagina',"webpagina's",'internetsite','internetsites','strona','strony','strona_internetowa','strony_internetowe','witryna','witryny','witryna_internetowa','witryny_internetowe')
            }
            $script:ObjectTypeLookup = @{}
            foreach ($canonical in $script:ObjectTypeMap.Keys) {
                # include canonical itself as accepted input
                $all = @($canonical) + $script:ObjectTypeMap[$canonical]
                foreach ($v in $all) {
                    if ([string]::IsNullOrWhiteSpace($v)) { continue }
                    $k = ($v -as [string]).Trim().ToLowerInvariant()
                    $k = $k -replace '[-\s]+','_'      # treat dashes/spaces like underscores
                    $script:ObjectTypeLookup[$k] = $canonical
                }
            }
        }

        $raw = ([string]$inputData).Trim()
        if ($raw.Length -eq 0) { return $raw }

        $k = $raw.ToLowerInvariant() -replace '[-\s]+','_'

        $lookup = $script:ObjectTypeLookup
        if ($lookup.ContainsKey($k)) {
            return $lookup[$k]
        }
        $allowed = ($script:ObjectTypeMap.Keys -join ', ')
        throw "Invalid core object type '$raw'. Allowed: $allowed"
}

#EndRegion '.\Private\Get-ObjectTypeFromCononical.ps1' 48
#Region '.\Private\Get-PhotoImageType.ps1' -1

function Get-PhotoImageType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName')]
        [string]$Path,

        [ValidateRange(16, 4096)]
        [int]$MaxBytes = 64
    )

    begin {
        function Test-Bytes {
            param(
                [byte[]]$Data,
                [int]$Offset,
                [byte[]]$Pattern
            )
            if ($null -eq $Data) { return $false }
            if ($Offset -lt 0) { return $false }
            if ($Data.Length -lt ($Offset + $Pattern.Length)) { return $false }
            for ($i = 0; $i -lt $Pattern.Length; $i++) {
                if ($Data[$Offset + $i] -ne $Pattern[$i]) { return $false }
            }
            return $true
        }

        function Get-Ascii {
            param([byte[]]$Data, [int]$Offset, [int]$Count)
            if ($Data.Length -lt ($Offset + $Count)) { return $null }
            return [System.Text.Encoding]::ASCII.GetString($Data, $Offset, $Count)
        }
    }

    process {
        # Resolve + reject non-files early
        $full = $null
        try { $full = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path }
        catch { return 'unknown' }

        $item = Get-Item -LiteralPath $full -ErrorAction SilentlyContinue
        if ($null -eq $item -or $item.PSIsContainer) { return 'unknown' }

        # Read a small header
        $buf = New-Object byte[] $MaxBytes
        $read = 0
        try {
            $fs = [System.IO.File]::Open($full, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try { $read = $fs.Read($buf, 0, $buf.Length) }
            finally { $fs.Dispose() }
        } catch {
            return 'unknown'
        }

        if ($read -lt 12) { return 'unknown' }  # need at least this much for WebP/ftyp checks
        $data = if ($read -eq $buf.Length) { $buf } else { $buf[0..($read-1)] }

        # JPEG: FF D8 FF
        if (Test-Bytes $data 0 ([byte[]](0xFF,0xD8,0xFF))) { return 'jpeg' }

        # PNG: 89 50 4E 47 0D 0A 1A 0A
        if (Test-Bytes $data 0 ([byte[]](0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A))) { return 'png' }

        # GIF: GIF87a / GIF89a
        $gif = Get-Ascii $data 0 6
        if ($gif -eq 'GIF87a' -or $gif -eq 'GIF89a') { return 'gif' }

        # WebP: RIFF....WEBP
        if ((Get-Ascii $data 0 4) -eq 'RIFF' -and (Get-Ascii $data 8 4) -eq 'WEBP') { return 'webp' }

        # HEIC/HEIF: ISOBMFF ftyp + major brand
        if ((Get-Ascii $data 4 4) -eq 'ftyp') {
            $brand = Get-Ascii $data 8 4
            # keep this list tight; expand if you want AVIF, etc.
            if ($brand -in @('heic','heix','hevc','hevx','mif1','msf1','heim','heis')) { return 'heic' }
        }

        return 'unknown'
    }
}
#EndRegion '.\Private\Get-PhotoImageType.ps1' 81
#Region '.\Private\Invoke-HuduRequest.ps1' -1

function Invoke-HuduRequest {
    <#
    .SYNOPSIS
    Main Hudu API function

    .DESCRIPTION
    Calls Hudu API with token

    .PARAMETER Method
    GET,POST,DELETE,PUT,etc

    .PARAMETER Params
    Hashtable of parameters

    .PARAMETER Body
    JSON encoded body string

    .PARAMETER Form
    Multipart form data

    .EXAMPLE
    Invoke-HuduRequest -Resource '/api/v1/articles' -Method GET
    #>
    [CmdletBinding()]
    Param(
        [Parameter()]
        [string]$Method = 'GET',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Resource,

        [Parameter()]
        [hashtable]$Params = @{},

        [Parameter()]
        [string]$Body,

        [Parameter()]
        [hashtable]$Form  
    )

    $HuduAPIKey = Get-HuduApiKey
    $HuduBaseURL = Get-HuduBaseURL

    # Assemble parameters
    $ParamCollection = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)

    # Sort parameters
    foreach ($Item in ($Params.GetEnumerator() | Sort-Object -CaseSensitive -Property Key)) {
        $ParamCollection.Add($Item.Key, $Item.Value)
    }

    # Query string
    $Request = $ParamCollection.ToString()

    $Headers = @{
        'x-api-key' = (New-Object PSCredential 'user', $HuduAPIKey).GetNetworkCredential().Password;
    }

    if (($Script:Int_HuduCustomHeaders | Measure-Object).count -gt 0){
        
        foreach($Entry in $Int_HuduCustomHeaders.GetEnumerator()) {
            $Headers[$Entry.Name] = $Entry.Value
        }
    }

    $ContentType = 'application/json; charset=utf-8'

    $Uri = '{0}{1}' -f $HuduBaseURL, $Resource
    # Make API call URI
    if ($Request) {
        $UriBuilder = [System.UriBuilder]$Uri
        $UriBuilder.Query = $Request
        $Uri = $UriBuilder.Uri
    }
    Write-Verbose ( '{0} [{1}]' -f $Method, $Uri )

    # One session for every request, so calls reuse the connection instead of a new TCP and TLS handshake each time
    if (-not $Script:Int_HuduWebSession) { $Script:Int_HuduWebSession = [Microsoft.PowerShell.Commands.WebRequestSession]::new() }

    $RestMethod = @{
        Method      = $Method
        Uri         = $Uri
        Headers     = $Headers
        ContentType = $ContentType
        WebSession  = $Script:Int_HuduWebSession
    }

    if ($Body) {
        $RestMethod.Body = $Body
        Write-Verbose $Body
    }

    if ($Form) {
        $RestMethod.Form = $Form
        Write-Verbose ( $Form | Out-String )
    }

    try {
        $Results = Invoke-RestMethod @RestMethod
    } catch {
        $errorMessage = $_.Exception.Message
        if ($errorMessage -ilike '*Retry later*' -or $errorMessage -ilike '*429*Too Many Requests*') {
            $windowLength = $script:HAPI_RATE_LIMIT_WINDOW_SECONDS ?? 300
            $secondsIntoWindow = [int][math]::Floor((Get-Date).TimeOfDay.TotalSeconds) % $windowLength
            $secondsUntilNextWindow = [math]::Max(0, $windowLength - $secondsIntoWindow)

            $jitter = Get-Random -Minimum 1 -Maximum 5
            $totalSleep = [math]::Max(0, $secondsUntilNextWindow + $jitter)
            Write-Host "Hudu API Rate limited; Sleeping for $totalSleep seconds to wait for next rate limit window..."
            Start-Sleep -Seconds $totalSleep
        } elseif ($errorMessage -ilike '*Not Found*') {
            return $null
        } else {
            if ($script:SKIP_HAPI_ERROR_RETRY -and $true -eq $script:SKIP_HAPI_ERROR_RETRY) { Write-Error "$_"; return $null }
            if ($script:SKIP_HAPI_POST_RETRY -and $Method -eq 'POST') { Write-Error "$_"; return $null }
            Write-APIErrorObject -name "$($resource ?? 'general')-$($method ?? 'unknown')" -ErrorObject @{
                exception = $_
                request = "$Method $Uri"
                resolution = "Trying again in $($script:HAPI_RETRY_DELAY_SECONDS ?? 5) seconds."
            }
            Start-Sleep -Seconds ($script:HAPI_RETRY_DELAY_SECONDS ?? 5)
        }

        try {
            $Results = Invoke-RestMethod @RestMethod
        } catch {
            Write-APIErrorObject -name "$($resource ?? 'general')-$($method ?? 'unknown')-retry" -ErrorObject @{
                exception = $_
                request = "$Method $Uri"
                resolution = "Retry failed as well. Handle this error here or avoid it prior."
            }
            Write-Error "$_"
            return $null
        }
    }


    $Results
}
#EndRegion '.\Private\Invoke-HuduRequest.ps1' 142
#Region '.\Private\Invoke-HuduRequestPaginated.ps1' -1

function Invoke-HuduRequestPaginated {
    <#
    .SYNOPSIS
    Paginated requests to Hudu API

    .DESCRIPTION
    Wraps Invoke-HuduRequest with page sizes

    .PARAMETER HuduRequest
    Request to paginate

    .PARAMETER Property
    Property name to return (don't specify to return entire response object)

    .PARAMETER PageSize
    Number of results to return per page (default 1000)

    #>
    [CmdletBinding()]
    Param(
        [hashtable]$HuduRequest,
        [string]$Property,
        [int]$PageSize = 1000
    )

    $i = 1
    do {
        $HuduRequest.Params.page = $i
        $HuduRequest.Params.page_size = $PageSize
        $Response = Invoke-HuduRequest @HuduRequest
        $i++
        if ($Property) {
            $Response.$Property
        }

        else {
            $Response
        }
    } while (($Property -and $Response.$Property.count % $PageSize -eq 0 -and $Response.$Property.count -ne 0) -or (!$Property -and $Response.count % $PageSize -eq 0 -and $Response.count -ne 0))
}
#EndRegion '.\Private\Invoke-HuduRequestPaginated.ps1' 41
#Region '.\Private\Set-ColorFromCanonical.ps1' -1


Function Set-ColorFromCanonical {
    param (
        [string] $inputData
    ) 
    if ([string]::IsNullOrWhiteSpace($inputData)) { return $null }
    if (-not $(get-variable -name 'script:ColorLookup' -scope 'script' -erroraction silentlycontinue)) {
        $script:ColorMap = [ordered]@{ # English, German, French, Italian, Spanish, Portuguese, Dutch, Polish
            Red = @('red','crimson','scarlet','rot','karminrot','scharlachrot','rouge','rouges','cramoisi','cramoisie','écarlate','ecarlate','rosso','rossa','rossi','rosse','cremisi','scarlatto','scarlatta','rojo','roja','rojos','rojas','carmesí','carmesi','escarlata','vermelho','vermelha','vermelhos','vermelhas','carmesim','escarlate','rood','rode','karmozijn','scharlaken','czerwony','czerwona','czerwone','karmazynowy')
            Blue = @('blue','navy','blau','marineblau','bleu','bleue','bleus','bleues','bleu_marine','blu','blu_navy','azul','azules','azul_marino','azuis','azul_marinho','blauw','blauwe','marineblauw','niebieski','niebieska','niebieskie','granatowy')
            Green = @('green','lime','grün','gruen','limettengrün','limettengruen','vert','verte','verts','vertes','vert_citron','verde','verdi','verde_lime','verdes','verde_lima','groen','groene','limoengroen','zielony','zielona','zielone','limonkowy')
            Yellow = @('yellow','gold','gelb','golden','jaune','or','doré','dore','giallo','gialla','gialli','gialle','oro','dorato','amarillo','amarilla','amarillos','amarillas','dorado','dorada','amarelo','amarela','amarelos','amarelas','ouro','dourado','dourada','geel','gele','goud','gouden','żółty','zolty','żółta','zolta','żółte','zolte','złoty','zloty')
            Purple = @('purple','violet','lila','violett','violette','pourpre','viola','porpora','púrpura','purpura','violeta','morado','morada','roxo','roxa','roxos','roxas','paars','paarse','fioletowy','fioletowa','fioletowe','purpurowy')
            Orange = @('orange','arancione','naranja','anaranjado','anaranjada','laranja','alaranjado','alaranjada','oranje','pomarańczowy','pomaranczowy','pomarańczowa','pomaranczowa')
            LightPink = @('light_pink','pink','baby_pink','hellrosa','rosa','babyrosa','rose_clair','rose','rose_pâle','rose_pale','rosa_chiaro','rosa_claro','rosa_clara','rosado','rosada','lichtroze','roze','babyroze','jasnoróżowy','jasnorozowy','różowy','rozowy')
            LightBlue = @('light_blue','baby_blue','sky_blue','hellblau','babyblau','himmelblau','bleu_clair','bleu_ciel','bleu_pâle','bleu_pale','azzurro','azzurra','azzurri','azzurre','blu_chiaro','azul_claro','azul_celeste','celeste','lichtblauw','hemelsblauw','babyblauw','jasnoniebieski','błękitny','blekitny')
            LightGreen = @('light_green','mint','mint_green','hellgrün','hellgruen','mintgrün','mintgruen','vert_clair','menthe','vert_menthe','verde_chiaro','menta','verde_menta','verde_claro','lichtgroen','muntgroen','jasnozielony','miętowy','mietowy')
            LightPurple = @('light_purple','lavender','lilac','helllila','lavendel','violet_clair','lavande','lilas','viola_chiaro','lavanda','lilla','morado_claro','morada_clara','lila','roxo_claro','roxa_clara','lilás','lichtpaars','jasnofioletowy','lawendowy')
            LightOrange = @('light_orange','peach','hellorange','pfirsich','orange_clair','pêche','peche','arancione_chiaro','pesca','naranja_claro','naranja_clara','melocotón','melocoton','durazno','laranja_claro','laranja_clara','pêssego','pessego','lichtoranje','perzik','jasnopomarańczowy','jasnopomaranczowy','brzoskwiniowy')
            LightYellow = @('light_yellow','cream','hellgelb','creme','cremefarben','jaune_clair','crème','giallo_chiaro','crema','amarillo_claro','amarilla_clara','amarelo_claro','amarela_clara','lichtgeel','jasnożółty','jasnozolty','kremowy')
            White = @('white','weiß','weiss','blanc','blanche','blancs','blanches','bianco','bianca','bianchi','bianche','blanco','blanca','blancos','blancas','branco','branca','brancos','brancas','wit','witte','biały','bialy','biała','biala','białe','biale')
            Grey = @('grey','gray','silver','grau','silber','gris','grise','argent','argenté','argente','grigio','grigia','grigi','grigie','argento','grises','plateado','plateada','plata','cinza','cinzento','cinzenta','prata','prateado','prateada','grijs','grijze','zilver','szary','szara','szare','srebrny','srebrna')
        }
        
    $script:ColorLookup = @{}
    foreach ($canonical in $script:ColorMap.Keys) {
        $all = @($canonical) + $script:ColorMap[$canonical]
        foreach ($v in $all) {
            if (-not $v) { continue }

            $k = $v.ToLowerInvariant()
            $k = $k -replace '[-\s]+','_'    # normalize separators
            $script:ColorLookup[$k] = $canonical
        }
    }        
    }

    $raw = ([string]$inputData).Trim()
    if ($raw.Length -eq 0) { return $raw }

    $key = $raw.ToLowerInvariant() -replace '[-\s]+','_'

    if ($script:ColorLookup.ContainsKey($key)) {
        return $script:ColorLookup[$key]
    }

    $allowed = ($script:ColorMap.Keys -join ', ')
    throw "Invalid color '$raw'. Allowed values: $allowed"
}
#EndRegion '.\Private\Set-ColorFromCanonical.ps1' 50
#Region '.\Private\Write-ErrorObject.ps1' -1


function Write-APIErrorObject {
    param (
        [Parameter(Mandatory)]
        [object]$ErrorObject,

        [Parameter()]
        [string]$Name = "unnamed",

        [Parameter()]
        [ValidateSet("Black","DarkBlue","DarkGreen","DarkCyan","DarkRed","DarkMagenta","DarkYellow","Gray","DarkGray","Blue","Green","Cyan","Red","Magenta","Yellow","White")]
        [string]$Color

    )
    <#
    .SYNOPSIS
    Unwraps and prints an object, error, and logs error to a specific file safely.
#>
    $stringOutput = try {
        $ErrorObject | Format-List -Force | Out-String
    } catch {
        "Failed to stringify object: $_"
    }

    $propertyDump = try {
        $props = $ErrorObject | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name
        $lines = foreach ($p in $props) {
            try {
                "$p = $($ErrorObject.$p)"
            } catch {
                "$p = <unreadable>"
            }
        }
        $lines -join "`n"
    } catch {
        "Failed to enumerate properties: $_"
    }

    $logContent = @"
==== OBJECT STRING ====
$stringOutput

==== PROPERTY DUMP ====
$propertyDump
"@
    Write-Verbose $logContent
    # Writing the log to disk and the host is opt-in, enabled by calling Set-HapiErrorsDirectory
    if ([string]::IsNullOrWhiteSpace($script:HAPI_ERRORS_DIRECTORY)) { return }

    $SafeName = ($Name -replace '[\\/:*?"<>|]', '_') -replace '\s+', ''
    if ($SafeName.Length -gt 60) {
        $SafeName = $SafeName.Substring(0, 60)
    }
    $fullPath = Join-Path $script:HAPI_ERRORS_DIRECTORY "${SafeName}_error_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    Set-Content -Path $fullPath -Value $logContent -Encoding UTF8

    if ($script:HAPI_ERROR_COLOR -and @("Black","DarkBlue","DarkGreen","DarkCyan","DarkRed","DarkMagenta","DarkYellow","Gray","DarkGray","Blue","Green","Cyan","Red","Magenta","Yellow","White") -contains $script:HAPI_ERROR_COLOR) {
        Write-Host "$logContent`nError written to $fullPath" -ForegroundColor $script:HAPI_ERROR_COLOR
    } elseif ($Color) {
        Write-Host "$logContent`nError written to $fullPath" -ForegroundColor $Color
    } else {
        Write-Host "$logContent"
    }
}
#EndRegion '.\Private\Write-ErrorObject.ps1' 65
#Region '.\Public\Copy-HuduProcedure.ps1' -1

function Copy-HuduProcedure {
    <#
    .SYNOPSIS
    Duplicate an existing process.

    .DESCRIPTION
    Calls POST /api/v1/procedures/{id}/duplicate to create a new company process
    by duplicating an existing process.

    .PARAMETER ProcedureId
    ID of the process to duplicate.

    .PARAMETER CompanyId
    Company ID for the new duplicated process.

    .PARAMETER Name
    Optional new name for the duplicated process.

    .PARAMETER Description
    Optional new description for the duplicated process.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Alias('Id')]
        [int]$ProcedureId,

        [Parameter(Mandatory)]
        [int]$CompanyId,

        [string]$Name,

        [string]$Description
    )

    $params = @{
        company_id = $CompanyId
    }

    if ($PSBoundParameters.ContainsKey('Name'))        { $params.name = $Name }
    if ($PSBoundParameters.ContainsKey('Description')) { $params.description = $Description }

    try {
        $res = Invoke-HuduRequest -Method POST -Resource "/api/v1/procedures/$ProcedureId/duplicate" -Params $params
        return ($res.procedure ?? $res)
    }
    catch {
        Write-Warning "Failed to duplicate procedure ID $ProcedureId $($_.Exception.Message)"
        return $null
    }
}
#EndRegion '.\Public\Copy-HuduProcedure.ps1' 52
#Region '.\Public\Get-HuduActivityLogs.ps1' -1

function Get-HuduActivityLogs {
    <#
    .SYNOPSIS
    Get activity logs for account

    .DESCRIPTION
    Calls Hudu API to retrieve activity logs with filters

    .PARAMETER UserId
    Filter logs by user_id

    .PARAMETER UserEmail
    Filter logs by email address

    .PARAMETER ResourceId
    Filter logs by resource id. Must be coupled with resource_type

    .PARAMETER ResourceType
    Filter logs by resource type (Asset, AssetPassword, Company, Article, etc.). Must be coupled with resource_id

    .PARAMETER ActionMessage
    Filter logs by action

    .PARAMETER StartDate
    Filter logs by start date. Converts string to ISO 8601 format

    .PARAMETER EndDate
    Filter logs by end date, should be coupled with start date to limit results

    .EXAMPLE
    Get-HuduActivityLogs -StartDate 2023-02-01

    #>
    [CmdletBinding()]
    Param (
        [Alias('user_id')]
        [Int]$UserId = '',
        [Alias('user_email')]
        [String]$UserEmail = '',
        [Alias('resource_id')]
        [Int]$ResourceId = '',
        [Alias('resource_type')]
        [String]$ResourceType = '',
        [Alias('action_message')]
        [String]$ActionMessage = '',
        [Alias('start_date')]
        [DateTime]$StartDate,
        [Alias('end_date')]
        [DateTime]$EndDate
    )

    $Params = @{}

    if ($UserId) { $Params.user_id = $UserId }
    if ($UserEmail) { $Params.user_email = $UserEmail }
    if ($ResourceId) { $Params.resource_id = $ResourceId }
    if ($ResourceType) { $Params.resource_type = $ResourceType }
    if ($ActionMessage) { $Params.action_message = $ActionMessage }
    if ($StartDate) {
        $ISO8601Date = $StartDate.ToString('o');
        $Params.start_date = $ISO8601Date
    }

    $HuduRequest = @{
        Method   = 'GET'
        Resource = '/api/v1/activity_logs'
        Params   = $Params
    }

    $AllActivity = Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -PageSize 200

    if ($EndDate) {
        $AllActivity = $AllActivity | Where-Object { $([DateTime]::Parse($_.created_at)) -le $EndDate }
    }

    return $AllActivity
}
#EndRegion '.\Public\Get-HuduActivityLogs.ps1' 78
#Region '.\Public\Get-HuduApiKey.ps1' -1

function Get-HuduApiKey {
    <#
    .SYNOPSIS
    Get Hudu API key

    .DESCRIPTION
    Returns Hudu API key in securestring format

    .EXAMPLE
    Get-HuduApiKey

    #>
    [CmdletBinding()]
    Param()
    if ($null -eq $Int_HuduAPIKey) {
        Write-Error 'No API key has been set. Please use New-HuduAPIKey to set it.'
    } else {
        $Int_HuduAPIKey
    }
}
#EndRegion '.\Public\Get-HuduApiKey.ps1' 21
#Region '.\Public\Get-HuduAppInfo.ps1' -1

function Get-HuduAppInfo {
    <#
    .SYNOPSIS
    Retrieve information regarding API

    .DESCRIPTION
    Calls Hudu API to retrieve version number and date

    .EXAMPLE
    Get-HuduAppInfo

    #>
    [CmdletBinding()]
    Param()

    [version]$script:HuduRequiredVersion = '2.21'
    
    try {
        Invoke-HuduRequest -Resource '/api/v1/api_info'
    } catch {
        [PSCustomObject]@{
            version = '0.0.0.0'
            date    = '2000-01-01'
        }
    }
}
#EndRegion '.\Public\Get-HuduAppInfo.ps1' 27
#Region '.\Public\Get-HuduArticles.ps1' -1

function Get-HuduArticles {
    <#
    .SYNOPSIS
    Get Knowledge Base Articles

    .DESCRIPTION
    Calls Hudu API to retrieve KB articles by Id or a list

    .PARAMETER Id
    Id of the Article

    .PARAMETER CompanyId
    Filter by company id

    .PARAMETER Name
    Filter by name of article

    .PARAMETER Slug
    Filter by slug of article

    .PARAMETER UpdatedAfter
    Get articles Updated After X datetime
    
    .PARAMETER UpdatedBefore
    Get articles Updated Before Y datetime

    .EXAMPLE
    Get-HuduArticles -Name 'Article name'
    get-huduarticles -UpdatedAfter $(get-date).AddDays(-3)

    #>
    [CmdletBinding()]
    Param (
        [Int]$Id = '',
        [Alias('company_id')]
        [Int]$CompanyId = '',
        [String]$Name = '',
        [String]$Slug,
        [datetime]$UpdatedAfter,
        [datetime]$UpdatedBefore
    )

    if ($Id) {
        Invoke-HuduRequest -Method get -Resource "/api/v1/articles/$Id"
    } else {
        $Params = @{}

        if ($CompanyId) { $Params.company_id = $CompanyId }
        if ($Name) { $Params.name = $Name }
        if ($Slug) { $Params.slug = $Slug }
        $updatedRange = Convert-ToHuduDateRange -Start $UpdatedAfter -End $UpdatedBefore
        if ($updatedRange -ne ',' -and -$null -ne $updatedRange) {
            $Params.updated_at = $updatedRange
        }
        
        $HuduRequest = @{
            Method   = 'GET'
            Resource = '/api/v1/articles'
            Params   = $Params
        }

        Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -Property articles -pageSize 100
    }
}
#EndRegion '.\Public\Get-HuduArticles.ps1' 65
#Region '.\Public\Get-HuduAssetLayoutFieldID.ps1' -1

function Get-HuduAssetLayoutFieldID {
    <#
    .SYNOPSIS
    Get Hudu Asset Layout Field ID

    .DESCRIPTION
    Retrieves ID for Hudu Asset Layout Fields

    .PARAMETER Name
    Name of Field

    .PARAMETER LayoutId
    Asset Layout Id

    .EXAMPLE
    Get-HuduAssetLayoutFieldID -Name 'Extra Info' -LayoutId 1

    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [String]$Name,
        [Alias('asset_layout_id')]
        [Parameter(Mandatory = $true)]
        [Int]$LayoutId
    )

    $Layout = Get-HuduAssetLayouts -LayoutId $LayoutId

    $Fields = [Collections.Generic.List[Object]]($Layout.fields)
    $Index = $Fields.FindIndex( { $args[0].label -eq $Name } )
    $Fields[$Index].id
}
#EndRegion '.\Public\Get-HuduAssetLayoutFieldID.ps1' 34
#Region '.\Public\Get-HuduAssetLayouts.ps1' -1

function Get-HuduAssetLayouts {
    <#
    .SYNOPSIS
    Get a list of Asset Layouts

    .DESCRIPTION
    Call Hudu API to retrieve asset layouts for server

    .PARAMETER Name
    Filter by name of Asset Layout

    .PARAMETER LayoutId
    Id of Asset Layout

    .PARAMETER Slug
    Filter by url slug

    .PARAMETER UpdatedAfter
    Get asset layouts Updated After X datetime
    
    .PARAMETER UpdatedBefore
    Get asset layouts Updated Before Y datetime

    .EXAMPLE
    Get-HuduAssetLayouts -Name 'Contacts'
    Get-HuduAssetLayouts -UpdatedBefore $(get-date).AddDays(-3)

    #>
    [CmdletBinding()]
    Param (
        [String]$Name,
        [Alias('id', 'layout_id')]
        [int]$LayoutId,
        [String]$Slug,
        [datetime]$UpdatedAfter,
        [datetime]$UpdatedBefore        
    )

    $HuduRequest = @{
        Resource = '/api/v1/asset_layouts'
        Method   = 'GET'
    }

    if ($LayoutId) {
        $HuduRequest.Resource = '{0}/{1}' -f $HuduRequest.Resource, $LayoutId
        $AssetLayout = Invoke-HuduRequest @HuduRequest
        return $AssetLayout.asset_layout
    } else {
        $Params = @{}
        if ($Name) { $Params.name = $Name }
        if ($Slug) { $Params.slug = $Slug }
        $updatedRange = Convert-ToHuduDateRange -Start $UpdatedAfter -End $UpdatedBefore
        if ($updatedRange -ne ',' -and -$null -ne $updatedRange) {
            $Params.updated_at = $updatedRange
        }

        $HuduRequest.Params = $Params

        $AssetLayouts = Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -Property 'asset_layouts' -PageSize 25

        if (!$Name -and !$Slug) {
            $script:AssetLayouts = $AssetLayouts | Sort-Object -Property name
        }
        $AssetLayouts
    }
}
#EndRegion '.\Public\Get-HuduAssetLayouts.ps1' 67
#Region '.\Public\Get-HuduAssets.ps1' -1

function Get-HuduAssets {
    <#
    .SYNOPSIS
    Get a list of Assets

    .DESCRIPTION
    Call Hudu API to retrieve Assets

    .PARAMETER Id
    Id of requested asset

    .PARAMETER AssetLayoutId
    Id of the requested asset layout

    .PARAMETER AssetLayout
    Name of the requested asset layout

    .PARAMETER CompanyId
    Id of the requested company

    .PARAMETER Name
    Filter by name

    .PARAMETER Archived
    Show archived results

    .PARAMETER PrimarySerial
    Filter by primary serial

    .PARAMETER Slug
    Filter by slug

    .PARAMETER UpdatedAfter
    Get Assets Updated After X datetime
    
    .PARAMETER UpdatedBefore
    Get Assets Updated Before Y datetime    

    .EXAMPLE
    Get-HuduAssets -AssetLayout 'Contacts'
    Get-Huduassets -UpdatedAfter $(Get-date).AddDays(-4) -UpdatedBefore $(get-date).AddHours(-1)
    Get-Huduassets -assetlayoutId 4 -UpdatedAfter $(Get-date).AddYears(-2) -UpdatedBefore $(get-date).AddYears(-1)

    #>
    [CmdletBinding()]
    Param (
        [ValidateRange(1, [int]::MaxValue)]
        [Int]$Id = '',
        [Alias('asset_layout_id')]
        [ValidateRange(1, [int]::MaxValue)]
        [Int]$AssetLayoutId = '',
        [string]$AssetLayout,
        [Alias('company_id')]
        [ValidateRange(1, [int]::MaxValue)]
        [Int]$CompanyId = '',
        [String]$Name = '',
        [switch]$Archived,
        [Alias('primary_serial')]
        [String]$PrimarySerial = '',
        [String]$Slug,
        [datetime]$UpdatedAfter,
        [datetime]$UpdatedBefore        
    )

    if ($AssetLayout) {
        if (!$script:AssetLayouts) { Get-HuduAssetLayouts | Out-Null }
        $AssetLayoutId = $script:AssetLayouts | Where-Object { $_.name -eq $AssetLayout } | Select-Object -ExpandProperty id
    }

    if ($id -and $CompanyId) {
        $HuduRequest = @{
            Resource = "/api/v1/companies/$CompanyId/assets/$Id"
            Method   = 'GET'
        }
        Invoke-HuduRequest @HuduRequest
    } else {
        $Params = @{}
        if ($CompanyId) { $Params.company_id = $CompanyId }
        if ($AssetLayoutId) { $Params.asset_layout_id = $AssetLayoutId }
        if ($Name) { $Params.name = $Name }
        if ($Archived.IsPresent) { $params.archived = $Archived.IsPresent }
        if ($PrimarySerial) { $Params.primary_serial = $PrimarySerial }
        if ($Id) { $Params.id = $Id }
        if ($Slug) { $Params.slug = $Slug }
        if ($UpdatedAfter -and $UpdatedBefore) {
            $updatedRange = Convert-ToHuduDateRange -Start $UpdatedAfter -End $UpdatedBefore
            if ($updatedRange -ne ',' -and -$null -ne $updatedRange) {
                $Params.updated_at = $updatedRange
            }
        } elseif ($UpdatedAfter -or $UpdatedBefore) {Write-Warning "Both UpdatedAfter and UpdatedBefore must be provided to filter Assets by updated date. The singular date param you provided will be ignored this time."}

        $HuduRequest = @{
            Resource = '/api/v1/assets'
            Method   = 'GET'
            Params   = $Params
        }
        Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -PageSize 500 -Property assets
    }
}
#EndRegion '.\Public\Get-HuduAssets.ps1' 100
#Region '.\Public\Get-HuduBaseURL.ps1' -1

function Get-HuduBaseURL {
    <#
    .SYNOPSIS
    Get Hudu Base URL

    .DESCRIPTION
    Returns Hudu Base URL

    .EXAMPLE
    Get-HuduBaseURL

    #>
    [CmdletBinding()]
    Param()
    if ($null -eq $Int_HuduBaseURL) {
        Write-Error 'No Base URL has been set. Please use New-HuduBaseURL to set it.'
    } else {
        $Int_HuduBaseURL
    }
}
#EndRegion '.\Public\Get-HuduBaseURL.ps1' 21
#Region '.\Public\Get-HuduCard.ps1' -1

function Get-HuduCard {
    <#
    .SYNOPSIS
    Get Integration Cards

    .DESCRIPTION
    Lookup cards with outside integration details

    .PARAMETER IntegrationSlug
    Identifier of outside integration

    .PARAMETER IntegrationId
    ID in the integration. Must be present, unless integration_identifier is set

    .PARAMETER IntegrationIdentifier
    Identifier in the integration (if integration_id is not set)

    .EXAMPLE
    Get-HuduCard -IntegrationSlug cw_manage -IntegrationId 1

    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [Alias('integration_slug')]
        [String]$IntegrationSlug,

        [Alias('integration_id')]
        [String]$IntegrationId,

        [Alias('integration_identifier')]
        [String]$IntegrationIdentifier
    )

    $Params = @{
        integration_slug = $IntegrationSlug
    }

    if ($IntegrationId) { $Params.integration_id = $IntegrationId }
    if ($IntegrationIdentifier) { $Params.integration_identifier = $IntegrationIdentifier }

    if (!$IntegrationId -and !$IntegrationIdentifier) {
        throw 'IntegrationId or IntegrationIdentifier required'
    }

    $HuduRequest = @{
        Method   = 'GET'
        Resource = '/api/v1/cards/lookup'
        Params   = $Params
    }

    Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -Property integrator_cards
}
#EndRegion '.\Public\Get-HuduCard.ps1' 54
#Region '.\Public\Get-HuduCompanies.ps1' -1

function Get-HuduCompanies {
    <#
    .SYNOPSIS
    Get a list of companies

    .DESCRIPTION
    Call Hudu API to retrieve company list

    .PARAMETER Id
    Filter companies by id

    .PARAMETER Name
    Filter companies by name

    .PARAMETER PhoneNumber
    filter companies by phone number

    .PARAMETER Website
    Filter companies by website

    .PARAMETER City
    Filter companies by city

    .PARAMETER State
    Filter companies by state

    .PARAMETER Search
    Filter by search query

    .PARAMETER Slug
    Filter by url slug

    .PARAMETER IdInIntegration
    Filter companies by id/identifier in PSA/RMM/outside integration

    .PARAMETER UpdatedAfter
    Get Companies Updated After X datetime
    
    .PARAMETER UpdatedBefore
    Get Companies Updated Before Y datetime

    .EXAMPLE
    Get-HuduCompanies -Search 'Vendor'
    Get-HuduCompanies -Updatedafter $(get-date).Addyears(-1)

    #>
    [CmdletBinding()]
    Param (
        [String]$Name = '',
        [Alias('phone_number')]
        [String]$PhoneNumber = '',
        [String]$Website = '',
        [String]$City = '',
        [String]$State = '',
        [Alias('id_in_integration')]
        [Int]$IdInIntegration = '',
        [Int]$Id = '',
        [string]$Search,
        [String]$Slug,
        [datetime]$UpdatedAfter,
        [datetime]$UpdatedBefore
    )

    if ($Id) {
        $Company = (Invoke-HuduRequest -Method get -Resource "/api/v1/companies/$Id").company
        return $Company
    } else {
        $Params = @{}
        if ($Name) { $Params.name = $Name }
        if ($PhoneNumber) { $Params.phone_number = $PhoneNumber }
        if ($Website) { $Params.website = $Website }
        if ($City) { $Params.city = $City }
        if ($State) { $Params.state = $State }
        if ($IdInIntegration) { $Params.id_in_integration = $IdInIntegration }
        if ($Search) { $Params.search = $Search }
        if ($Slug) { $Params.slug = $Slug }
        $updatedRange = Convert-ToHuduDateRange -Start $UpdatedAfter -End $UpdatedBefore
        if ($updatedRange -ne ',' -and -$null -ne $updatedRange) {
            $Params.updated_at = $updatedRange
        }

        $HuduRequest = @{
            Method   = 'GET'
            Resource = '/api/v1/companies'
            Params   = $Params
        }

        Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -Property 'companies'
    }
}
#EndRegion '.\Public\Get-HuduCompanies.ps1' 91
#Region '.\Public\Get-HuduExpirations.ps1' -1

function Get-HuduExpirations {
    <#
    .SYNOPSIS
    Get expirations for account

    .DESCRIPTION
    Calls Hudu API to retrieve expirations

    .PARAMETER CompanyId
    Filter expirations by company_id

    .PARAMETER ExpirationType
    Filter expirations by expiration type (undeclared, domain, ssl_certificate, warranty, asset_field, article_expiration)

    .PARAMETER ResourceId
    Filter logs by resource id. Must be coupled with resource_type

    .PARAMETER ResourceType
    Filter logs by resource type (Asset, AssetPassword, Company, Article, etc.). Must be coupled with resource_id

    .EXAMPLE
    Get-HuduExpirations -ExpirationType domain

    #>
    [CmdletBinding()]
    Param (
        [Alias('company_id')]
        [Int]$CompanyId = '',

        [ValidateSet('undeclared', 'domain', 'ssl_certificate', 'warranty', 'asset_field', 'article_expiration')]
        [Alias('expiration_type')]
        [String]$ExpirationType = '',

        [Alias('resource_id')]
        [Int]$ResourceId = '',

        [Alias('resource_type')]
        [String]$ResourceType = ''
    )

    $Params = @{}

    if ($CompanyId) { $Params.company_id = $CompanyId }
    if ($ExpirationType) { $Params.expiration_type = $ExpirationType }
    if ($ResourceType) { $Params.resource_type = $ResourceType }
    if ($ResourceId) { $Params.resource_id = $ResourceId }

    $HuduRequest = @{
        Method   = 'GET'
        Resource = '/api/v1/expirations'
        Params   = $Params
    }

    Invoke-HuduRequestPaginated -HuduRequest $HuduRequest
}
#EndRegion '.\Public\Get-HuduExpirations.ps1' 56
#Region '.\Public\Get-HuduExports.ps1' -1

function Get-HuduExports {
    [CmdletBinding()]
    param(
        [int]$id
    )
    if ($null -ne $id -and $id -ge 1){
        Invoke-HuduRequest -Method 'GET' -Resource "/api/v1/exports/$id"
    } else {
        Invoke-HuduRequest -Method 'GET' -Resource '/api/v1/exports'
    }
}
#EndRegion '.\Public\Get-HuduExports.ps1' 12
#Region '.\Public\Get-HuduFeatureAvailability.ps1' -1

function Get-HuduFeatureAvailability {
    <#
    .SYNOPSIS
    Safely Determine if a Core Hudu Feature is Available

    .DESCRIPTION
    Uses Hudu API to query core objects to determine their accessibility.
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('corefeature')]
        [ValidateScript({Assert-AllowedObjectType -InputType $_ -AllowedCanonicals @(
                "VlanZone", "Vlan", "Procedure", "Website", "RackStorage", "Network", "IpAddress", "Article", "Company", "Asset", "AssetPassword", "Photo","PublicPhoto","Racks"
        )})][String]$Core_Feature
    )

    $ObjectType = "$(Get-ObjectTypeFromCononical -inputData $Core_Feature)"
    if ($ObjectType -eq 'Article') {
        return Test-HuduArticleFeatureAvailability
    }

    $Resource = switch ($ObjectType) {
        "VlanZone"      { "/api/v1/ip_addresses" }
        "Vlan"          { "/api/v1/ip_addresses" }
        "IpAddress"     { "/api/v1/ip_addresses" }
        "Network"       { "/api/v1/ip_addresses" }

        "Procedure"     { "/api/v1/procedures" }
        "Website"       { "/api/v1/websites" }
        "RackStorage"   { "/api/v1/rack_storages" }
        "PublicPhoto"   { "/api/v1/public_photos" }
        "Photo"         { "/api/v1/photos" }
        "Article"       { "/api/v1/articles" }
        "Company"       { "/api/v1/companies" }
        "Asset"         { "/api/v1/assets" }
        "AssetPassword" { "/api/v1/asset_passwords" }
        default          { throw "Unsupported core feature: $Core_Feature" }
    }

    try {
        $Result = Invoke-HuduFeatureAvailabilityProbe -Resource $Resource
        return -not (Test-HuduFeatureDisabledMessage -InputObject $Result)
    } catch {
        if (Test-HuduFeatureDisabledMessage -InputObject $_) {
            return $false
        }

        if ($ObjectType -eq 'AssetPassword' -and (Test-HuduFeatureAvailabilityBadCredentials -InputObject $_)) {
            Write-Verbose 'Password feature availability probe returned Bad credentials. Treating passwords as unavailable for this API key/instance.'
            return $false
        }

        throw
    }
}

function Invoke-HuduFeatureAvailabilityProbe {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Resource,

        [hashtable]$Params = @{},

        [ValidateSet('GET', 'POST', 'DELETE')]
        [string]$Method = 'GET',

        [string]$Body
    )

    $ParamCollection = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)
    $QueryParams = @{}
    
    if ($Method -eq 'GET' -and $Resource -notlike '/api/v1/ip_addresses*') { # ip addresses / ipam not paginated
        $QueryParams.page = '1'
        $QueryParams.page_size = '1'
    }

    foreach ($Item in $Params.GetEnumerator()) {
        $QueryParams[$Item.Key] = $Item.Value
    }

    foreach ($Item in ($QueryParams.GetEnumerator() | Sort-Object -CaseSensitive -Property Key)) {
        $ParamCollection.Add($Item.Key, $Item.Value)
    }

    $UriBuilder = [System.UriBuilder]('{0}{1}' -f (Get-HuduBaseURL), $Resource)
    $UriBuilder.Query = $ParamCollection.ToString()

    Invoke-HuduFeatureAvailabilityRequest -Method $Method -Uri $UriBuilder.Uri -Body $Body
}

function Invoke-HuduFeatureAvailabilityRequest {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('GET', 'POST', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [uri]$Uri,

        [string]$Body
    )

    $HuduAPIKey = Get-HuduApiKey
    $Headers = @{
        'x-api-key' = (New-Object PSCredential 'user', $HuduAPIKey).GetNetworkCredential().Password
    }

    if (($Script:Int_HuduCustomHeaders | Measure-Object).count -gt 0) {
        foreach ($Entry in $Int_HuduCustomHeaders.GetEnumerator()) {
            $Headers[$Entry.Name] = $Entry.Value
        }
    }

    $Request = @{
        Method      = $Method
        Uri         = $Uri
        Headers     = $Headers
        ContentType = 'application/json; charset=utf-8'
        ErrorAction = 'Stop'
    }

    if ($Body) {
        $Request.Body = $Body
    }

    Invoke-RestMethod @Request
}

function Test-HuduArticleFeatureAvailability {
    [CmdletBinding()]
    Param ()

    $CentralAvailable = Test-HuduArticleScopeFeatureAvailability -TreatServerErrorAsUnavailable

    $CompanyId = Get-HuduFeatureAvailabilityProbeCompanyId
    if (-not $CompanyId) {
        $ProbeCompany = $null
        try {
            $ProbeCompany = New-HuduFeatureAvailabilityProbeCompany
            $companyArticleAvailable = Test-HuduArticleScopeFeatureAvailability -Params @{ company_id = $ProbeCompany.id } -TreatServerErrorAsUnavailable
        } catch {
            $companyArticleAvailable = $false
        } finally {
            if ($ProbeCompany -and $ProbeCompany.id) {
                Remove-HuduFeatureAvailabilityProbeCompany -Id $ProbeCompany.id
            }
        }
    } else {
        $companyArticleAvailable = Test-HuduArticleScopeFeatureAvailability -Params @{ company_id = $CompanyId } -TreatServerErrorAsUnavailable
    }

    return [PSCustomObject]@{
        CompanyKB = $companyArticleAvailable
        CentralKB = $CentralAvailable
    }
}

function Test-HuduArticleScopeFeatureAvailability {
    [CmdletBinding()]
    Param (
        [hashtable]$Params = @{},

        [switch]$TreatServerErrorAsUnavailable
    )

    Test-HuduArticleCreateProbeResult -Params $Params -TreatServerErrorAsUnavailable:$TreatServerErrorAsUnavailable
}

function Test-HuduArticleCreateProbeResult {
    [CmdletBinding()]
    Param (
        [hashtable]$Params = @{},

        [switch]$TreatServerErrorAsUnavailable
    )

    $Article = [ordered]@{
        article = [ordered]@{
            name      = 'hudu-feature-availability-probe'
            content   = 'Temporary article probe created by Get-HuduFeatureAvailability.'
            folder_id = -1
        }
    }

    if ($Params.ContainsKey('company_id')) {
        $Article.article.Add('company_id', $Params.company_id)
    }

    try {
        $Result = Invoke-HuduFeatureAvailabilityProbe -Resource '/api/v1/articles' -Method POST -Body ($Article | ConvertTo-Json -Depth 10)
        Remove-HuduFeatureAvailabilityProbeArticle -InputObject $Result
        return -not (Test-HuduFeatureDisabledMessage -InputObject $Result)
    } catch {
        if (Test-HuduFeatureDisabledMessage -InputObject $_) {
            Write-Verbose 'Article create probe returned a disabled-feature response.'
            return $false
        }

        if (Test-HuduFeatureAvailabilityValidationError -InputObject $_) {
            Write-Verbose 'Article create probe reached validation, so the article feature is available.'
            return $true
        }

        if ($TreatServerErrorAsUnavailable.IsPresent -and (Test-HuduFeatureAvailabilityServerError -InputObject $_)) {
            Write-Verbose ("Article create probe returned a server error response: {0}" -f (Get-HuduFeatureAvailabilityDetails -InputObject $_))
            return $false
        }

        throw
    }
}

function Remove-HuduFeatureAvailabilityProbeArticle {
    [CmdletBinding()]
    Param (
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return
    }

    $Article = $InputObject.article ?? $InputObject
    if (-not $Article -or -not $Article.id) {
        return
    }

    $Uri = [System.Uri]('{0}/api/v1/articles/{1}' -f (Get-HuduBaseURL).TrimEnd('/'), $Article.id)
    try {
        $null = Invoke-HuduFeatureAvailabilityRequest -Method DELETE -Uri $Uri
    } catch {
        Write-Warning "Failed to delete temporary Hudu feature availability probe article id $($Article.id). Delete it manually. $($_.Exception.Message)"
    }
}

function New-HuduFeatureAvailabilityProbeCompany {
    [CmdletBinding()]
    Param ()

    $Name = 'hudu-feature-availability-probe-{0}' -f ([guid]::NewGuid().ToString('N').Substring(0, 12))
    $Company = [ordered]@{
        company = [ordered]@{
            name  = $Name
            notes = 'Temporary company created by Get-HuduFeatureAvailability to probe company-scoped KB availability.'
        }
    }

    $Uri = [System.Uri]('{0}/api/v1/companies' -f (Get-HuduBaseURL).TrimEnd('/'))
    $Result = Invoke-HuduFeatureAvailabilityRequest -Method POST -Uri $Uri -Body ($Company | ConvertTo-Json -Depth 10)
    $ProbeCompany = $Result.company ?? $Result

    if (-not $ProbeCompany -or -not $ProbeCompany.id) {
        throw 'Failed to create temporary Hudu company for feature availability probe.'
    }

    return $ProbeCompany
}

function Remove-HuduFeatureAvailabilityProbeCompany {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [int]$Id
    )

    $Uri = [System.Uri]('{0}/api/v1/companies/{1}' -f (Get-HuduBaseURL).TrimEnd('/'), $Id)
    try {
        $null = Invoke-HuduFeatureAvailabilityRequest -Method DELETE -Uri $Uri
    } catch {
        Write-Warning "Failed to delete temporary Hudu feature availability probe company id $Id. Delete it manually. $($_.Exception.Message)"
        throw
    }
}

function Test-HuduFeatureAvailabilityProbeResult {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Resource,

        [hashtable]$Params = @{},

        [switch]$TreatServerErrorAsUnavailable
    )

    try {
        $Result = Invoke-HuduFeatureAvailabilityProbe -Resource $Resource -Params $Params
        return -not (Test-HuduFeatureDisabledMessage -InputObject $Result)
    } catch {
        if (Test-HuduFeatureDisabledMessage -InputObject $_) {
            Write-Verbose ("Feature availability probe for {0} returned a disabled-feature response." -f $Resource)
            return $false
        }

        if ($TreatServerErrorAsUnavailable.IsPresent -and (Test-HuduFeatureAvailabilityServerError -InputObject $_)) {
            Write-Verbose ("Feature availability probe for {0} returned a server error response: {1}" -f $Resource, (Get-HuduFeatureAvailabilityDetails -InputObject $_))
            return $false
        }

        throw
    }
}

function Get-HuduFeatureAvailabilityProbeCompanyId {
    [CmdletBinding()]
    Param ()

    $Result = Invoke-HuduFeatureAvailabilityProbe -Resource '/api/v1/companies'
    $Companies = @($Result.companies)

    if (-not $Companies) {
        $Companies = @($Result)
    }

    $Company = $Companies | Where-Object { $null -ne $_.id } | Select-Object -First 1
    if ($Company) {
        return $Company.id
    }

    return $null
}

function Test-HuduFeatureDisabledMessage {
    [CmdletBinding()]
    Param (
        [AllowNull()]
        [object]$InputObject
    )

    $Details = Get-HuduFeatureAvailabilityDetails -InputObject $InputObject
    return (
        $Details -ilike '*disabled for this instance*' -or
        $Details -imatch '(?m)"error"\s*:\s*"[^"]+\s+is disabled"' -or
        $Details -imatch '(?m)\b[\w\s/-]+\s+is disabled\b' -or
        $Details -imatch '(?m)\b[\w\s/-]+\s+(is\s+)?turned off\b' -or
        $Details -imatch '(?m)\b[\w\s/-]+\s+is not enabled\b'
    )
}

function Test-HuduFeatureAvailabilityServerError {
    [CmdletBinding()]
    Param (
        [AllowNull()]
        [object]$InputObject
    )

    $Details = Get-HuduFeatureAvailabilityDetails -InputObject $InputObject
    return (
        $Details -ilike '*500*Internal Server Error*' -or
        $Details -ilike '*InternalServerError*' -or
        $Details -ilike '*Response status code does not indicate success: 500*'
    )
}

function Test-HuduFeatureAvailabilityValidationError {
    [CmdletBinding()]
    Param (
        [AllowNull()]
        [object]$InputObject
    )

    $Details = Get-HuduFeatureAvailabilityDetails -InputObject $InputObject
    return (
        $Details -ilike '*422*' -or
        $Details -ilike '*Unprocessable Entity*' -or
        $Details -ilike '*unprocessable_entity*' -or
        $Details -ilike '*validation*' -or
        $Details -ilike '*can''t be blank*' -or
        $Details -ilike '*cannot be blank*' -or
        $Details -ilike '*is too short*' -or
        $Details -ilike '*param is missing*' -or
        $Details -ilike '*value is empty*' -or
        $Details -ilike '*required parameter*'
    )
}

function Test-HuduFeatureAvailabilityBadCredentials {
    [CmdletBinding()]
    Param (
        [AllowNull()]
        [object]$InputObject
    )

    $Details = Get-HuduFeatureAvailabilityDetails -InputObject $InputObject
    return ($Details -imatch '(?m)\bBad credentials\b')
}

function Get-HuduFeatureAvailabilityDetails {
    [CmdletBinding()]
    Param (
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return ''
    }

    $Parts = [System.Collections.Generic.List[string]]::new()

    if ($InputObject -is [System.Management.Automation.ErrorRecord]) {
        Add-HuduFeatureAvailabilityDetail -Parts $Parts -Value $InputObject.Exception.Message
        Add-HuduFeatureAvailabilityDetail -Parts $Parts -Value $InputObject.ErrorDetails
        Add-HuduFeatureAvailabilityDetail -Parts $Parts -Value $InputObject.ErrorDetails.Message
        Add-HuduFeatureAvailabilityDetail -Parts $Parts -Value $InputObject.Exception.Response
        Add-HuduFeatureAvailabilityDetail -Parts $Parts -Value (Get-HuduFeatureAvailabilityResponseBody -Response $InputObject.Exception.Response)
    } else {
        Add-HuduFeatureAvailabilityDetail -Parts $Parts -Value $InputObject
    }

    return ($Parts -join "`n")
}

function Add-HuduFeatureAvailabilityDetail {
    Param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Parts,

        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return
    }

    if ($Value -is [string]) {
        if (-not [string]::IsNullOrWhiteSpace($Value)) {
            $Parts.Add($Value)
        }
        return
    }

    try {
        $Json = $Value | ConvertTo-Json -Depth 20 -Compress -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace($Json)) {
            $Parts.Add($Json)
        }
    } catch {
        $StringValue = $Value.ToString()
        if (-not [string]::IsNullOrWhiteSpace($StringValue)) {
            $Parts.Add($StringValue)
        }
    }
}

function Get-HuduFeatureAvailabilityResponseBody {
    Param (
        [AllowNull()]
        [object]$Response
    )

    if ($null -eq $Response) {
        return $null
    }

    try {
        if ($Response.Content -and ($Response.Content | Get-Member -Name ReadAsStringAsync -MemberType Method)) {
            return $Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        }
    } catch {
        return $null
    }

    try {
        if ($Response.GetType().GetMethod('GetResponseStream')) {
            $Stream = $Response.GetResponseStream()
            if ($null -eq $Stream) {
                return $null
            }

            $Reader = [System.IO.StreamReader]::new($Stream)
            try {
                return $Reader.ReadToEnd()
            } finally {
                $Reader.Dispose()
            }
        }
    } catch {
        return $null
    }

    return $null
}
#EndRegion '.\Public\Get-HuduFeatureAvailability.ps1' 493
#Region '.\Public\Get-HuduFlags.ps1' -1

function Get-HuduFlags {
<#
.SYNOPSIS
Gets Flags from Hudu.

.DESCRIPTION
Retrieves a single Flag by ID, or lists Flags with optional filtering by flag type,
target object type/id, and description. Results are paginated when listing.

.PARAMETER Id
Return a single Flag by ID.

.PARAMETER FlagTypeId
Filter flags by Flag Type ID.

.PARAMETER flagable_type
Filter by the target object type the flag is attached to (e.g., Company, Asset).
This value is normalized to Hudu's canonical flagable_type.

.PARAMETER flagable_id
Filter by the target object ID the flag is attached to.

.PARAMETER Description
Filter by description text (exact match behavior depends on API; treat as an exact filter unless documented otherwise).

.EXAMPLE
Get-HuduFlags
# List all flags (paginated)

.EXAMPLE
Get-HuduFlags -FlagTypeId 5
# List all flags using flag type 5

.EXAMPLE
Get-HuduFlags -flagable_type Company -flagable_id 123
# List all flags attached to company 123

.EXAMPLE
Get-HuduFlags -Id 77
# Get a single flag by ID

.NOTES
API Endpoints:
- GET /api/v1/flags
- GET /api/v1/flags/{id}
#>

    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ById')]
        [Alias('FlagId','flag_id')]
        [int]$Id,

        [Parameter(ParameterSetName = 'List')]
        [Alias("Flag_Type_ID","FlagType_ID","Flag_TypeId")]
        [int]$FlagTypeId,

        [Parameter(ParameterSetName = 'List')]
        [Alias('flagabletype',"flaggable_type","flaggabletype","Flag_type","FlagType")]
        [ValidateSet('asset', 'assets', 'anlage', 'objekt', 'actif', 'bene', 'activo', 'website', 'webseite', 'site', 'sito', 'sitio', 'article', 'articles', 'kb', 'knowledgebase', 'artikel', 'articolo', 'artículo', 'assetpassword', 'asset_password', 'password', 'passwort', 'motdepasse', 'contraseña', 'company', 'companies', 'firma', 'entreprise', 'azienda', 'empresa', 'procedure', 'process', 'verfahren', 'procédure', 'procedura', 'procedimiento', 'rackstorage', 'rack_storage', 'rack', 'rackstorages', 'armoire', 'network', 'netzwerk', 'réseau', 'rete', 'red', 'ipaddress', 'ip_address', 'ip', 'ipadresse', 'adresseip', 'indirizzoip', 'direccionip', 'vlan', 'vlans', 'vlanzone', 'vlan_zone', 'zone', 'zonevlan',IgnoreCase = $true)]
        [string]$flagable_type,

        [Parameter(ParameterSetName = 'List')]
        [Alias("FlaggableId","flaggable_id","flagableid")]
        [int]$flagable_id,

        [string]$Description
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            $resp = Invoke-HuduRequest -Method GET -Resource "/api/v1/flags/$Id"
            return ($resp.flag ?? $resp ?? $null)
        }

        $params = @{}
        if ($PSBoundParameters.ContainsKey('FlagTypeId'))   { $params.flag_type_id  = $FlagTypeId }
        if ($PSBoundParameters.ContainsKey('flagable_type')) {
            $params.flagable_type = $(Get-ObjectTypeFromCononical -inputData $flagable_type)
        }
        if ($PSBoundParameters.ContainsKey('flagable_id'))   { $params.flagable_id   = $flagable_id }
        if ($PSBoundParameters.ContainsKey('Description'))  { $params.description   = $Description }
        $params.page = 1
        $params.page_size = 1000
        $req = @{
            Method   = 'GET'
            Resource = "/api/v1/flags"
            Params   = $params
        }

        $resp = Invoke-HuduRequestPaginated -HuduRequest $req -Property 'flags'
        return $resp
    }
}
#EndRegion '.\Public\Get-HuduFlags.ps1' 95
#Region '.\Public\Get-HuduFlagTypes.ps1' -1


function Get-HuduFlagTypes {
<#
.SYNOPSIS
Gets Flag Types from Hudu.

.DESCRIPTION
Retrieves Flag Types by ID or lists Flag Types with optional filtering. When listing,
filters match exact values for name/color/slug when provided. Results are paginated.

.PARAMETER Id
Return a single Flag Type by ID.

.PARAMETER Name
Filter by exact Flag Type name.

.PARAMETER Color
Filter by exact color value (canonicalized to Hudu).

.PARAMETER Slug
Filter by exact slug value.

.EXAMPLE
Get-HuduFlagTypes
# List all flag types

.EXAMPLE
Get-HuduFlagTypes -Name "Security Risk"
# Find the "Security Risk" flag type

.EXAMPLE
Get-HuduFlagTypes -Id 12
# Get a specific flag type by ID

.NOTES
API Endpoints:
- GET /api/v1/flag_types
- GET /api/v1/flag_types/{id}
#>

    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ById')]
        [Alias('FlagTypeId','flag_type_id')]
        [int]$Id,

        [Parameter(ParameterSetName = 'List')]
        [string]$Name,

        [Parameter()]
        [ValidateSet('red', 'crimson', 'scarlet', 'rot', 'karminrot', 'scharlachrot', 'rouge', 'cramoisi', 'écarlate', 'rosso', 'cremisi', 'scarlatto', 'rojo', 'carmesí', 'escarlata', 'blue', 'navy', 'blau', 'marineblau', 'bleu', 'bleu marine', 'blu', 'blu navy', 'azul', 'azul marino', 'green', 'lime', 'grün', 'limettengrün', 'vert', 'vert citron', 'verde', 'verde lime', 'verde lima', 'yellow', 'gold', 'gelb', 'jaune', 'or', 'giallo', 'oro', 'amarillo', 'purple', 'violet', 'lila', 'violett', 'pourpre', 'viola', 'porpora', 'púrpura', 'violeta', 'orange', 'arancione', 'naranja', 'light pink', 'pink', 'baby pink', 'hellrosa', 'rosa', 'rose clair', 'rose', 'rosa chiaro', 'rosa claro', 'light blue', 'baby blue', 'sky blue', 'hellblau', 'babyblau', 'himmelblau', 'bleu clair', 'bleu ciel', 'azzurro', 'blu chiaro', 'azul claro', 'celeste', 'light green', 'mint', 'hellgrün', 'mintgrün', 'vert clair', 'menthe', 'verde chiaro', 'menta', 'verde claro', 'light purple', 'lavender', 'helllila', 'lavendel', 'violet clair', 'lavande', 'viola chiaro', 'lavanda', 'morado claro', 'light orange', 'peach', 'hellorange', 'pfirsich', 'orange clair', 'pêche', 'arancione chiaro', 'pesca', 'naranja claro', 'melocotón', 'light yellow', 'cream', 'hellgelb', 'creme', 'jaune clair', 'crème', 'giallo chiaro', 'crema', 'amarillo claro', 'white', 'weiß', 'blanc', 'bianco', 'blanco', 'grey', 'gray', 'silver', 'grau', 'silber', 'gris', 'argent', 'grigio', 'argento', 'plateado', 'lightpink', 'lightblue', 'lightgreen', 'lightpurple', 'lightorange', 'lightyellow',IgnoreCase = $true)]
        [string]$Color,

        [string]$Slug
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            $resp = Invoke-HuduRequest -Method GET -Resource "/api/v1/flag_types/$Id"
            return ($resp.flag_type ?? $resp)
        }

        $params = @{}
        if ($PSBoundParameters.ContainsKey('Name'))      { $params.name       = $Name }
        if ($PSBoundParameters.ContainsKey('Color'))     { 
            $params.color      = $(Set-ColorFromCanonical -inputData $Color) 
        }
        if ($PSBoundParameters.ContainsKey('Slug'))      { $params.slug       = $Slug }
        $params.page = 1
        $params.page_size = 1000
        $req = @{
            Method   = 'GET'
            Resource = "/api/v1/flag_types"
            Params   = $params
        }

        Invoke-HuduRequestPaginated -HuduRequest $req -Property 'flag_types'
    }
}
#EndRegion '.\Public\Get-HuduFlagTypes.ps1' 80
#Region '.\Public\Get-HuduFolderMap.ps1' -1

function Get-HuduFolderMap {
    [CmdletBinding()]
    Param (
        [Alias('company_id')]
        [Int]$CompanyId = ''
    )

    if ($CompanyId) {
        $FoldersRaw = Get-HuduFolders -company_id $CompanyId
        $SubFolders = Get-HuduCompanyFolders -FoldersRaw $FoldersRaw
    } else {
        $FoldersRaw = Get-HuduFolders
        $FoldersProcessed = $FoldersRaw | Where-Object { $null -eq $_.company_id }
        $SubFolders = Get-HuduCompanyFolders -FoldersRaw $FoldersProcessed
    }

    return $SubFolders
}
#EndRegion '.\Public\Get-HuduFolderMap.ps1' 19
#Region '.\Public\Get-HuduFolders.ps1' -1

function Get-HuduFolders {
    <#
    .SYNOPSIS
    Get a list of Folders

    .DESCRIPTION
    Calls Hudu API to retrieve folders

    .PARAMETER Id
    Id of the folder

    .PARAMETER Name
    Filter by name

    .PARAMETER CompanyId
    Filter by company_id

    .PARAMETER folderType
    Filter by folder_type. Accepts "article" or "photo", default is "article"

    .EXAMPLE
    Get-HuduFolders

    #>
    [CmdletBinding()]
    Param (
        [Nullable[int]]$Id,
        [String]$Name,
        [Alias('company_id')]
        [Nullable[int]]$CompanyId,
        [ValidateSet("article","photo", ignoreCase = $true)]
        [Alias('folder_type')]
        [string]$folderType="article"
    )

    if ($PSBoundParameters.ContainsKey('id')) {
        $Folder = Invoke-HuduRequest -Method get -Resource "/api/v1/folders/$id"
        return $Folder.Folder
    } else {
        $Params = @{}

        if ($PSBoundParameters.ContainsKey('CompanyId')) { $Params.company_id = $CompanyId }
        if ($PSBoundParameters.ContainsKey('Name')) { $Params.name = $Name }
        $Params.folder_type = "$folderType".ToLower()

        $HuduRequest = @{
            Method   = 'GET'
            Resource = '/api/v1/folders'
            Params   = $Params
        }
        Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -Property folders
    }
}
#EndRegion '.\Public\Get-HuduFolders.ps1' 54
#Region '.\Public\Get-HuduGroups.ps1' -1

function Get-HuduGroups {
    <#
    .SYNOPSIS
    Retrieve Hudu groups.

    .DESCRIPTION
    Calls the Hudu API to return groups.  
    You can fetch a single group by Id, or filter/search across all groups.

    .PARAMETER Id
    The numeric ID of the group to retrieve.

    .PARAMETER Name
    Name of the group (for filtering).

    .PARAMETER Search
    Search string to filter groups by.

    .PARAMETER Default
    Boolean flag to return only default groups.

    .EXAMPLE
    Get-HuduGroups
    Retrieves all groups.

    .EXAMPLE
    Get-HuduGroups -Id 123
    Retrieves the group with ID 123.

    .EXAMPLE
    Get-HuduGroups -Search "Technicians"
    Returns all groups matching the word "Technicians".
    #>
    [CmdletBinding()]
    Param (
        [Int]$Id,
        [String]$Name,
        [String]$Search,
        [bool]$Default
    )

    if ($id) {
        return $(Invoke-HuduRequest -Method get -Resource "/api/v1/groups/$id").group
    } else {
        $Params = @{}

        if ($CompanyId) { $Params.company_id = $CompanyId }
        if ($Search) { $Params.search = $Search }
        if ($Default) { $Params.default = $Default }

        $HuduRequest = @{
            Method   = 'GET'
            Resource = '/api/v1/groups'
            Params   = $Params
        }
        Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -property groups
    }
}
#EndRegion '.\Public\Get-HuduGroups.ps1' 59
#Region '.\Public\Get-HuduIntegrationMatchers.ps1' -1

function Get-HuduIntegrationMatchers {
    <#
    .SYNOPSIS
    List matchers for an integration

    .DESCRIPTION
    Calls Hudu API to get list of integration matching

    .PARAMETER IntegrationId
    ID of the integration. Can be found in the URL when editing an integration

    .PARAMETER Matched
    Filter on whether the company already been matched

    .PARAMETER SyncId
    Filter by ID of the record in the integration. This is used if the id that the integration uses is an integer.

    .PARAMETER Identifier
    Filter by Identifier in the integration (if sync_id is not set). This is used if the id that the integration uses is a string.

    .PARAMETER CompanyId
    Filter on company id

    .EXAMPLE
    Get-HuduIntegrationMatchers -IntegrationId 1

    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [int]$IntegrationId,

        [switch]$Matched,

        [int]$SyncId = '',

        [string]$Identifier = '',

        [int]$CompanyId
    )

    $Params = @{
        integration_id = $IntegrationId
    }

    if ($Matched.IsPresent) { $Params.matched = 'true' }
    if ($CompanyId) { $Params.company_id = $CompanyId }
    if ($Identifier) { $Params.identifier = $Identifier }
    if ($SyncId) { $Params.sync_id = $SyncId }

    $HuduRequest = @{
        Method   = 'GET'
        Resource = '/api/v1/matchers'
        Params   = $Params
    }
    Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -Property 'matchers'
}
#EndRegion '.\Public\Get-HuduIntegrationMatchers.ps1' 58
#Region '.\Public\Get-HuduIPAddresses.ps1' -1

function Get-HuduIPAddresses {
<#
.SYNOPSIS
Retrieve Hudu IP address records.

.DESCRIPTION
Gets one or more Hudu IPAM IP address objects.  
If -Id is supplied, returns a single record (or $null if not found).  
Without -Id, applies any provided filters and returns a collection.

.PARAMETER Id
IP address record ID to retrieve (exact match).

.PARAMETER Address
IP address (exact string match, e.g. '192.168.10.15').

.PARAMETER Status
IP status string as used by Hudu (e.g. 'active', 'reserved', 'available').
Value is lowercased before request.

.PARAMETER FQDN
Fully Qualified Domain Name to filter on (exact match).

.PARAMETER AssetId
Filter by related Asset ID.

.PARAMETER NetworkId
Filter by parent Network ID.

.PARAMETER CompanyId
Filter by Company ID.

.PARAMETER CreatedAfter
Only include IPs created on/after this UTC datetime.

.PARAMETER CreatedBefore
Only include IPs created on/before this UTC datetime.

.PARAMETER UpdatedAfter
Only include IPs updated on/after this UTC datetime.

.PARAMETER UpdatedBefore
Only include IPs updated on/before this UTC datetime.

.OUTPUTS
pscustomobject (single object when -Id is used) or an array of pscustomobject.

.EXAMPLE
Get-HuduIPAddresses -Id 1234

.EXAMPLE
Get-HuduIPAddresses -CompanyId 42 -NetworkId 7 -Status reserved

.EXAMPLE
# Filter by date range (created)
Get-HuduIPAddresses -CreatedAfter (Get-Date).AddDays(-7) -CreatedBefore (Get-Date)

.NOTES
Created*/Updated* pairs are converted to the API’s 'start,end' format via Convert-ToHuduDateRange.
If no filters are passed (and no -Id), all IPs are requested (server-side limits may apply).
#>
    [CmdletBinding()]
    param(
        [int]$Id,
        [string]$NetworkId,
        [string]$Address,
        [string]$Status,
        [string]$FQDN,
        [int]$AssetID,
        [int]$CompanyID,
        [datetime]$CreatedAfter,
        [datetime]$CreatedBefore,
        [datetime]$UpdatedAfter,
        [datetime]$UpdatedBefore        
    )
    $Params = @{}
    if ($NetworkId){$params["network_id"]=$NetworkId}
    if ($Address){$params["address"]=$Address}
    if ($Status){$params["status"]="$Status".ToLower()}
    if ($FQDN){$params["fqdn"]=$FQDN}
    if ($AssetID){$params["asset_id"]=$AssetID}
    if ($CompanyID){$params["company_id"]=$CompanyID}

    $createdRange = if ($CreatedAfter -and $CreatedBefore) {Convert-ToHuduDateRange -Start $CreatedAfter -End $CreatedBefore}
    if ($createdRange -ne ',' -and -$null -ne $createdRange) {
        $Params.created_at = $createdRange
    }

    $updatedRange = if ($UpdatedAfter -and $UpdatedBefore) {Convert-ToHuduDateRange -Start $UpdatedAfter -End $UpdatedBefore}
    if ($updatedRange -ne ',' -and -$null -ne $updatedRange) {
        $Params.updated_at = $updatedRange
    }
    $HuduRequest = if ($Id) {
        @{
            Method   = 'GET'
            Resource = "/api/v1/ip_addresses/$Id"
        }
    } else {
        @{
            Method   = 'GET'
            Resource = "/api/v1/ip_addresses"
            Params   = if ($Params.Count -gt 0) { $Params } else { $null }
        }
    }

    $addresses = Invoke-HuduRequest @HuduRequest

    return $addresses
}
#EndRegion '.\Public\Get-HuduIPAddresses.ps1' 110
#Region '.\Public\Get-HuduLabels.ps1' -1

function Get-HuduLabels {
<#
.SYNOPSIS
Gets Labels from Hudu.

.DESCRIPTION
Retrieves a single Label by ID, or lists Labels with optional filtering by label
type, target record, user, and created/updated dates.

.PARAMETER Id
Return a single Label by ID.

.PARAMETER LabelTypeId
Filter labels by Label Type ID.

.PARAMETER Labelable_Type
Filter by the target object type the label is attached to.

.PARAMETER Labelable_Id
Filter by the target object ID the label is attached to.

.PARAMETER UserId
Filter by the ID of the user who applied the label.

.PARAMETER CreatedAt
Filter by creation date (YYYY-MM-DD or ISO datetime).

.PARAMETER UpdatedAt
Filter by update date (YYYY-MM-DD or ISO datetime).

.PARAMETER Page
Return a specific page instead of auto-paginating all results.

.PARAMETER PageSize
Number of results per page. Defaults to 1000 when auto-paginating.

.EXAMPLE
Get-HuduLabels

.EXAMPLE
Get-HuduLabels -LabelTypeId 5

.EXAMPLE
Get-HuduLabels -Labelable_Type Asset -Labelable_Id 123

.EXAMPLE
Get-HuduLabels -Id 77

.NOTES
API Endpoints:
- GET /api/v1/labels
- GET /api/v1/labels/{id}
#>

    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ById')]
        [Alias('LabelId','label_id')]
        [int]$Id,

        [Parameter(ParameterSetName = 'List')]
        [Alias('label_type_id','labeltype_id','label_typeid','label_type','type_id','typeid')]
        [int]$LabelTypeId,

        [Parameter(ParameterSetName = 'List')]
        [Alias('object_type','objectType','target_type','targetType')]
        [ValidateScript({ Assert-AllowedObjectType -InputType $_ -AllowedCanonicals @(
            'Article', 'Asset', 'AssetPassword', 'Website', 'IpAddress', 'Vlan', 'VlanZone', 'Procedure', 'Network', 'RackStorage'
        ) })]
        [string]$Labelable_Type,

        [Parameter(ParameterSetName = 'List')]
        [Alias('object_id','objectID','target_id','targetId')]
        [int]$Labelable_Id,

        [Parameter(ParameterSetName = 'List')]
        [Alias('user_id')]
        [int]$UserId,

        [Parameter(ParameterSetName = 'List')]
        [Alias('created_at')]
        [string]$CreatedAt,

        [Parameter(ParameterSetName = 'List')]
        [Alias('updated_at')]
        [string]$UpdatedAt,

        [Parameter(ParameterSetName = 'List')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Page,

        [Parameter(ParameterSetName = 'List')]
        [Alias('page_size')]
        [ValidateRange(1, 1000)]
        [int]$PageSize = 1000
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            $resp = Invoke-HuduRequest -Method GET -Resource "/api/v1/labels/$Id"
            return ($resp.label ?? $resp)
        }

        $params = @{}
        if ($PSBoundParameters.ContainsKey('LabelTypeId'))    { $params.label_type_id  = $LabelTypeId }
        if ($PSBoundParameters.ContainsKey('Labelable_Type')) { $params.labelable_type = Get-ObjectTypeFromCononical -inputData $Labelable_Type }
        if ($PSBoundParameters.ContainsKey('Labelable_Id'))   { $params.labelable_id   = $Labelable_Id }
        if ($PSBoundParameters.ContainsKey('UserId'))         { $params.user_id        = $UserId }
        if ($PSBoundParameters.ContainsKey('CreatedAt'))      { $params.created_at     = $CreatedAt }
        if ($PSBoundParameters.ContainsKey('UpdatedAt'))      { $params.updated_at     = $UpdatedAt }

        $req = @{
            Method   = 'GET'
            Resource = "/api/v1/labels"
            Params   = $params
        }

        if ($PSBoundParameters.ContainsKey('Page')) {
            $params.page = $Page
            $params.page_size = $PageSize
            $resp = Invoke-HuduRequest @req
            return ($resp.labels ?? $resp)
        }

        Invoke-HuduRequestPaginated -HuduRequest $req -Property 'labels' -PageSize $PageSize
    }
}
#EndRegion '.\Public\Get-HuduLabels.ps1' 128
#Region '.\Public\Get-HuduLabelTypes.ps1' -1

function Get-HuduLabelTypes {
<#
.SYNOPSIS
Gets Label Types from Hudu.

.DESCRIPTION
Retrieves Label Types by ID or lists Label Types with optional filtering. When
listing, filters match exact values for name/color/slug when provided.

.PARAMETER Id
Return a single Label Type by ID.

.PARAMETER Name
Filter by exact Label Type name.

.PARAMETER Color
Filter by exact color value, such as #0000ff.

.PARAMETER Slug
Filter by exact slug value.

.PARAMETER CreatedAt
Filter by creation date (YYYY-MM-DD or ISO datetime).

.PARAMETER UpdatedAt
Filter by update date (YYYY-MM-DD or ISO datetime).

.PARAMETER Page
Return a specific page instead of auto-paginating all results.

.PARAMETER PageSize
Number of results per page. Defaults to 1000 when auto-paginating.

.EXAMPLE
Get-HuduLabelTypes

.EXAMPLE
Get-HuduLabelTypes -Name "Critical"

.EXAMPLE
Get-HuduLabelTypes -Id 12

.NOTES
API Endpoints:
- GET /api/v1/label_types
- GET /api/v1/label_types/{id}
#>

    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'ById')]
        [Alias('LabelTypeId','label_type_id','labeltype_id','label_typeid','type_id','typeid')]
        [int]$Id,

        [Parameter(ParameterSetName = 'List')]
        [string]$Name,

        [Parameter(ParameterSetName = 'List')]
        [ValidateNotNullOrEmpty()]
        [string]$Color,

        [Parameter(ParameterSetName = 'List')]
        [string]$Slug,

        [Parameter(ParameterSetName = 'List')]
        [Alias('created_at')]
        [string]$CreatedAt,

        [Parameter(ParameterSetName = 'List')]
        [Alias('updated_at')]
        [string]$UpdatedAt,

        [Parameter(ParameterSetName = 'List')]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Page,

        [Parameter(ParameterSetName = 'List')]
        [Alias('page_size')]
        [ValidateRange(1, 1000)]
        [int]$PageSize = 1000
    )

    process {
        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            $resp = Invoke-HuduRequest -Method GET -Resource "/api/v1/label_types/$Id"
            return ($resp.label_type ?? $resp)
        }

        $params = @{}
        if ($PSBoundParameters.ContainsKey('Name'))      { $params.name       = $Name }
        if ($PSBoundParameters.ContainsKey('Color'))     { $params.color      = ConvertTo-HuduLabelColor -Color $Color }
        if ($PSBoundParameters.ContainsKey('Slug'))      { $params.slug       = $Slug }
        if ($PSBoundParameters.ContainsKey('CreatedAt')) { $params.created_at = $CreatedAt }
        if ($PSBoundParameters.ContainsKey('UpdatedAt')) { $params.updated_at = $UpdatedAt }

        $req = @{
            Method   = 'GET'
            Resource = "/api/v1/label_types"
            Params   = $params
        }

        if ($PSBoundParameters.ContainsKey('Page')) {
            $params.page = $Page
            $params.page_size = $PageSize
            $resp = Invoke-HuduRequest @req
            return ($resp.label_types ?? $resp)
        }

        Invoke-HuduRequestPaginated -HuduRequest $req -Property 'label_types' -PageSize $PageSize
    }
}
#EndRegion '.\Public\Get-HuduLabelTypes.ps1' 112
#Region '.\Public\Get-HuduLists.ps1' -1

function Get-HuduLists {
    <#
    .SYNOPSIS
    Get a list of Hudu Lists or a List by ID

    .DESCRIPTION
    Calls the Hudu API to retrieve all Lists. Optionally filter by exact name or retrieve a single list by ID.

    .PARAMETER Id
    ID of the list to retrieve

    .PARAMETER Name
    Filter by exact list name (optional)

    .EXAMPLE
    Get-HuduLists -Id 123

    .EXAMPLE
    Get-HuduLists

    .EXAMPLE
    Get-HuduLists -Name "Device Status"
    #>
    [CmdletBinding()]
    param(
        [int]$Id,
        [string]$Name
    )

    if ($Id) {
        try {
            return Invoke-HuduRequest -Method GET -Resource "/api/v1/lists/$Id"
        } catch {
            Write-Warning "Failed to retrieve list with ID $Id"
            return $null
        }
    }

    $lists = Invoke-HuduRequest -Method GET -Resource "/api/v1/lists"

    if ($Name) {
        $match = $lists | Where-Object { $_.name -eq $Name }
        if ($match) {
            return $match
        }
        # Write-Warning "No list found with name '$Name'"
        return $null
    }

    return $lists
}
#EndRegion '.\Public\Get-HuduLists.ps1' 52
#Region '.\Public\Get-HuduMagicDashes.ps1' -1

function Get-HuduMagicDashes {
    <#
    .SYNOPSIS
    Get all Magic Dash Items

    .DESCRIPTION
    Call Hudu API to retrieve Magic Dashes

    .PARAMETER CompanyId
    Filter by company id

    .PARAMETER Title
    Filter by title

    .EXAMPLE
    Get-HuduMagicDashes -Title 'Microsoft 365 - ...'

    #>
    Param (
        [Alias('company_id')]
        [Int]$CompanyId,
        [String]$Title
    )

    $Params = @{}

    if ($CompanyId) { $Params.company_id = $CompanyId }
    if ($Title) { $Params.title = $Title }

    $HuduRequest = @{
        Method   = 'GET'
        Resource = '/api/v1/magic_dash'
        Params   = $Params
    }
    Invoke-HuduRequestPaginated -HuduRequest $HuduRequest
}
#EndRegion '.\Public\Get-HuduMagicDashes.ps1' 37
#Region '.\Public\Get-HuduNetworks.ps1' -1



function Get-HuduNetworks {
<#
.SYNOPSIS
Retrieve Hudu network by ID or networks.

.DESCRIPTION
Gets a single network by ID, or lists networks filtered by one or more criteria.
When -Id is provided, performs GET /api/v1/networks/{id}. Otherwise performs
GET /api/v1/networks with query parameters built from the provided filters.
Supports created/updated date range filtering via Convert-ToHuduDateRange.

.PARAMETER Id
Network ID. When supplied, returns only that network.

.PARAMETER CompanyId
Filter by company ID.

.PARAMETER Slug
Filter by slug.

.PARAMETER Name
Filter by network name (exact match as supported by the API).

.PARAMETER NetworkType
Filter by numeric network type.

.PARAMETER Address
Filter by CIDR/address string.

.PARAMETER LocationId
Filter by location ID.

.PARAMETER Archived
Filter archived state (True/False).

.PARAMETER CreatedAfter
Only include networks created on or after this date/time.

.PARAMETER CreatedBefore
Only include networks created on or before this date/time.

.PARAMETER UpdatedAfter
Only include networks updated on or after this date/time.

.PARAMETER UpdatedBefore
Only include networks updated on or before this date/time.

.EXAMPLE
Get-HuduNetworks -Id 123

.EXAMPLE
Get-HuduNetworks -CompanyId 42 -LocationId 7 -Archived $false

.EXAMPLE
Get-HuduNetworks -CreatedAfter ([datetime]'2025-08-01') -UpdatedBefore ([datetime]'2025-08-15')
#>
    [CmdletBinding()]
    param (
        [int]$Id,
        [int]$CompanyId,
        [string]$Slug,
        [string]$Name,
        [int]$NetworkType,
        [string]$Address,
        [int]$LocationID,
        [bool]$Archived,
        [datetime]$CreatedAfter,
        [datetime]$CreatedBefore,
        [datetime]$UpdatedAfter,
        [datetime]$UpdatedBefore
    )

    $BaseResource = "/api/v1/networks"

    $Params = @{}
    if ($CompanyId) { $Params["company_id"] = $CompanyId }
    if ($Slug) { $Params["slug"] = $Slug }
    if ($Name) { $Params["name"] = $Name }
    if ($NetworkType) { $Params["network_type"] = $NetworkType }
    if ($Address) { $Params["address"] = $Address }
    if ($LocationID) { $Params["location_id"] = $LocationID }
    if ($Archived) { $Params["archived"] = $Archived }

    $createdRange = Convert-ToHuduDateRange -Start $CreatedAfter -End $CreatedBefore
    if ($createdRange -ne ',' -and -$null -ne $createdRange) {
        $Params.created_at = $createdRange
    }

    $updatedRange = Convert-ToHuduDateRange -Start $UpdatedAfter -End $UpdatedBefore
    if ($updatedRange -ne ',' -and -$null -ne $updatedRange) {
        $Params.updated_at = $updatedRange
    }
    
    $HuduRequest = if ($Id) {
        @{
            Method   = 'GET'
            Resource = "$BaseResource/$Id"
        }
    } else {
        @{
            Method   = 'GET'
            Resource = "$BaseResource"
            Params   = if ($Params.Count -gt 0) { $Params } else { $null }
        }
    }

    Invoke-HuduRequest @HuduRequest
}
#EndRegion '.\Public\Get-HuduNetworks.ps1' 111
#Region '.\Public\Get-HuduObjectByUrl.ps1' -1

function Get-HuduObjectByUrl {
    <#
    .SYNOPSIS
    Get Hudu object from URL

    .DESCRIPTION
    Calls Hudu API to retrieve object based on URL string

    .PARAMETER Url
    Url to retrieve object from

    .EXAMPLE
    Get-HuduObject -Url https://your-hudu-server/a/some-asset-1z8z7a

    #>
    [CmdletBinding()]
    Param (
        [uri]$Url
    )

    if ((Get-HuduBaseURL) -match $Url.Authority) {
        $null, $Type, $Slug = $Url.PathAndQuery -split '/'

        $SlugSplat = @{
            Slug = $Slug
        }

        switch ($Type) {
            'a' {
                # Asset
                Get-HuduAssets @SlugSplat
            }
            'admin' {
                # Admin path
                $null, $null, $Type, $Slug = $Url.PathAndQuery -split '/'
                $SlugSplat = @{
                    Slug = $Slug
                }
                switch ($Type) {
                    'asset_layouts' {
                        # Asset layouts
                        Get-HuduAssetLayouts @SlugSplat
                    }
                }
            }
            'c' {
                # Company
                Get-HuduCompanies @SlugSplat
            }
            'kba' {
                # KB article
                Get-HuduArticles @SlugSplat
            }
            'passwords' {
                # Passwords
                Get-HuduPasswords @SlugSplat
            }
            'websites' {
                # Website
                Get-HuduWebsites @SlugSplat
            }
            default {
                Write-Error "Unsupported object type $Type"
            }
        }
    } else {
        Write-Error 'Provided URL does not match Hudu Base URL'
    }
}
#EndRegion '.\Public\Get-HuduObjectByUrl.ps1' 70
#Region '.\Public\Get-HuduPasswordFolders.ps1' -1

function Get-HuduPasswordFolders {
    <#
    .SYNOPSIS
    Retrieve password folders.

    .DESCRIPTION
    Calls the Hudu API to return password folders.  
    You can fetch a single folder by Id, or filter by name/company.

    .PARAMETER Id
    The numeric ID of the folder to retrieve.

    .PARAMETER Name
    Filter by folder name.

    .PARAMETER CompanyId
    Filter by company ID.

    .EXAMPLE
    Get-HuduPasswordFolders
    Retrieves all password folders.

    .EXAMPLE
    Get-HuduPasswordFolders -Id 12
    Retrieves the folder with ID 12.

    .EXAMPLE
    Get-HuduPasswordFolders -CompanyId 5
    Retrieves folders belonging to company with ID 5.
    #>
    [CmdletBinding()]
    Param (
        [Int]$Id,
        [String]$Name,
        [String]$Search,
        [Alias('company_id')]
        [Int]$CompanyId
    )

    if ($id) {
        $Folder = Invoke-HuduRequest -Method get -Resource "/api/v1/password_folders/$id"
        return $Folder.password_folder
    } else {
        $Params = @{}

        if ($CompanyId) { $Params.company_id = $CompanyId }
        if ($Name) { $Params.name = $Name }

        $HuduRequest = @{
            Method   = 'GET'
            Resource = '/api/v1/password_folders'
            Params   = $Params
        }
        Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -Property password_folders
    }
}
#EndRegion '.\Public\Get-HuduPasswordFolders.ps1' 57
#Region '.\Public\Get-HuduPasswords.ps1' -1

function Get-HuduPasswords {
    <#
    .SYNOPSIS
    Get a list of Passwords

    .DESCRIPTION
    Calls Hudu API to list password assets

    .PARAMETER Id
    Id of the password

    .PARAMETER CompanyId
    Filter by company id

    .PARAMETER Name
    Filter by password name

    .PARAMETER Slug
    Filter by url slug

    .PARAMETER Search
    Filter by search query

    .PARAMETER UpdatedAfter
    Get passwords Updated After X datetime
    
    .PARAMETER UpdatedBefore
    Get passwords Updated Before Y datetime    

    .EXAMPLE
    Get-HuduPasswords -CompanyId 1
    Get-HuduPasswords -UpdatedAfter $(get-date).AddDays(-3)


    #>
    [CmdletBinding()]
    Param (
        [Int]$Id,

        [Alias('company_id')]
        [Int]$CompanyId,

        [String]$Name,

        [String]$Slug,

        [string]$Search,
        [datetime]$UpdatedAfter,
        [datetime]$UpdatedBefore
    )

    if ($Id) {
        $Password = Invoke-HuduRequest -Method get -Resource "/api/v1/asset_passwords/$id"
        return $Password
    } else {
        $Params = @{}
        if ($CompanyId) { $Params.company_id = $CompanyId }
        if ($Name) { $Params.name = $Name }
        if ($Slug) { $Params.slug = $Slug }
        if ($Search) { $Params.search = $Search }
        $updatedRange = Convert-ToHuduDateRange -Start $UpdatedAfter -End $UpdatedBefore
        if ($updatedRange -ne ',' -and -$null -ne $updatedRange) {
            $Params.updated_at = $updatedRange
        }        
    }

    $HuduRequest = @{
        Method   = 'GET'
        Resource = '/api/v1/asset_passwords'
        Params   = $Params
    }
    Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -Property 'asset_passwords'
}
#EndRegion '.\Public\Get-HuduPasswords.ps1' 74
#Region '.\Public\Get-HuduPhotos.ps1' -1

function Get-HuduPhotos {
    <#
    .SYNOPSIS
    Get a list of photos or a single photo, optionally downloading files.

    .DESCRIPTION
    Calls Hudu API to retrieve photos. Supports filtering
    If -Download is specified with -Id (single) or without (list), downloads photo files using /photos/{id}?download=true.

    .PARAMETER Id
    ID of the Photo to retrieve (or download if -Download is specified).

    .PARAMETER CompanyId
    Filter by company ID.

    .PARAMETER Photoable_Type
    Filter by photoable type (Company, Asset, Article, etc).

    .PARAMETER Photoable_Id
    Filter by photoable record ID.

    .PARAMETER FolderId
    Filter by folder ID.

    .PARAMETER Archived
    $true = only archived, $false = only non-archived, $null = omit param (API defaults to non-archived only).

    .PARAMETER CreatedAt
    Filter by creation date. Accepts "YYYY-MM-DD" or "start,end" (YYYY-MM-DD,YYYY-MM-DD).

    .PARAMETER UpdatedAt
    Filter by update date. Accepts "YYYY-MM-DD" or "start,end" (YYYY-MM-DD,YYYY-MM-DD).

    .PARAMETER Download
    If specified, downloads photo file(s) to OutDir.

    .PARAMETER OutDir
    Directory to download photos into. Default current directory.

    .EXAMPLE
    Get-HuduPhotos -CompanyId 123

    .EXAMPLE
    Get-HuduPhotos -Photoable_Type Asset -Photoable_Id 456 -Download -OutDir "$env:TEMP\photos"

    .EXAMPLE
    Get-HuduPhotos -Id 999 -Download
    #>
    [CmdletBinding()]
    param(
        [int]$Id,

        [int]$CompanyId,
        [Alias('uploadabletype','recordtype','PhotoableType','uploadable_type','record_type')]
        [ValidateScript({Assert-AllowedObjectType -InputType $_ -AllowedCanonicals @(
                "Website", "RackStorage", "IpAddress", "Article", "Company", "Asset", "AssetPassword"
        )})]    
        [string]$Photoable_Type,
        [Alias('record_id','uploadable_id','recordid','PhotoableId','uploadableid')]
        [int]$Photoable_Id,
        [int]$FolderId,

        [Nullable[bool]]$Archived,
        [datetime]$createdBefore,
        [datetime]$createdAfter,
        [datetime]$UpdatedBefore,
        [datetime]$UpdatedAfter,

        [switch]$Download,
        [string]$OutDir = '.'
    )

    [version]$script:Version = $script:Version ?? [version]((Get-HuduAppInfo).version)


    if ($script:Version -lt [version]'2.41.0') {
        write-warning "Get-HuduPhotos: Hudu version $($script:Version) is below 2.41.0; Skipping."
        if ($id){ return $null } else { return @() }
    }

    $params = @{}
    if ($PSBoundParameters.ContainsKey('CompanyId')) { $params.company_id = $CompanyId }
    if ($PSBoundParameters.ContainsKey('Caption'))   { $params.caption = $Caption }
    if ($PSBoundParameters.ContainsKey('Pinned'))      { $params.pinned = [bool]$Pinned }
    if ($PSBoundParameters.ContainsKey('FolderId'))  { $params.folder_id = $FolderId }
    if ($PSBoundParameters.ContainsKey('archived'))  { $params.archived = [bool]$Archived }
 

    if ($PSBoundParameters.ContainsKey('Photoable_Type')) { 
        $params.photoable_type = $(Get-ObjectTypeFromCononical -inputData $Photoable_Type) 
    }
    if ($PSBoundParameters.ContainsKey('Photoable_Id')) { $params.photoable_id = $Photoable_Id }

    $updatedRange = Convert-ToHuduDateRange -Start $UpdatedAfter -End $UpdatedBefore
    if ($updatedRange -ne ',' -and -$null -ne $updatedRange) {
        $Params.updated_at = $updatedRange
    }
    $createdRange = Convert-ToHuduDateRange -Start $createdAfter -End $createdBefore
    if ($createdRange -ne ',' -and -$null -ne $createdRange) {
        $Params.created_at = $createdRange
    }    
    if ($Id) {
        $result = Invoke-HuduRequest -Method Get -Resource "/api/v1/photos/$Id"
        $Photos = @($result.photo ?? $result)
    } else {
        $Photos = Invoke-HuduRequestPaginated -hudurequest @{
            Method   = 'GET'
            Resource = '/api/v1/photos'
            params    = $params
        }
    }

    if ($Download) {
        $OutDir = if ([string]::IsNullOrWhiteSpace($OutDir)) { (Get-Location).Path } else { $OutDir }
        $OutDir = (New-Item -ItemType Directory -Path $OutDir -Force).FullName

        $Headers = @{ 'x-api-key' = (New-Object PSCredential 'user', $(Get-HuduApiKey)).GetNetworkCredential().Password }

        foreach ($p in @($($Photos.photos ?? $photos.photo ?? $Photos))) {
            $label = $p.caption
            if ([string]::IsNullOrWhiteSpace($label)) { $label = "photo-$($p.id)" }
            $safe = ($label -replace '[<>:"/\\|?*\x00-\x1F]', '_').Trim()
            if ([string]::IsNullOrWhiteSpace($safe)) { $safe = "photo-$($p.id)" }

            $destinationPath = Join-Path -Path $OutDir -ChildPath "$safe-$($p.id).bin"

            $fileUrl = "$($script:HuduBaseUrl ?? $(get-hudubaseurl))/api/v1/photos/$($p.id)?download=true"

            try {
                Invoke-WebRequest -Uri $fileUrl -OutFile $destinationPath -Headers $Headers -MaximumRedirection 5 -ErrorAction Stop | Out-Null
                $imageType = $null; $imageType = Get-PhotoImageType -Path $destinationPath;
                if ($null -ne $imageType -and $imageType -ne 'unknown') {
                    $newPath = [System.IO.Path]::ChangeExtension($destinationPath, $imageType)
                    Move-Item -LiteralPath $destinationPath -Destination $newPath -Force
                    $destinationPath = $newPath
                }


                Write-Verbose "Downloaded '$($p.id)' to '$destinationPath'"

                if (Test-Path -LiteralPath $destinationPath) {
                    $p | Add-Member -MemberType NoteProperty -Name localPath -Value $destinationPath -Force
                }
            } catch {
                Write-Warning "Failed to download photo '$($p.id)' from '$fileUrl': $($_.Exception.Message)"
            }
        }
    }

    $photosOut = $(($Id ? ($Photos[0]) : $Photos))

    return $photosOut.photos ?? $photosOut.photo ?? $photosOut
}
#EndRegion '.\Public\Get-HuduPhotos.ps1' 154
#Region '.\Public\Get-HuduProcedures.ps1' -1

function Get-HuduProcedures {
    <#
    .SYNOPSIS
    Get Hudu processes and runs.

    .DESCRIPTION
    Retrieves processes (templates) and runs (active instances).

    On newer Hudu versions, the API distinguishes between:
    - process: a template
    - run: an active instance created from a process

    Deprecated parameters are still accepted for compatibility, but a warning
    is emitted and they are translated to the newer API parameters when possible.
    #>
    [CmdletBinding()]
    param (
        [int]$Id,
        [int]$CompanyId,
        [string]$Name,
        [string]$Slug,

        [ValidateSet('process','run','all')]
        [string]$Type,

        [ValidateSet('global','company')]
        [string]$ProcessScope,

        [int]$ParentProcessId,

        [string]$CreatedAt,
        [string]$UpdatedAt,

        [bool]$Archived,

        [int]$PageSize,

        # deprecated
        [string]$GlobalTemplate,
        [int]$CompanyTemplate,
        [int]$ParentProcedureId
    )

    if ($Id) {
        try {
            $res = Invoke-HuduRequest -Method GET -Resource "/api/v1/procedures/$Id"
            return ($res.procedure ?? $res)
        }
        catch {
            Write-Warning "Failed to retrieve procedure ID $Id- $($_.Exception.Message)"
            return $null
        }
    }

    $params = @{}

    if ($PSBoundParameters.ContainsKey('Name'))            { $params.name = $Name }
    if ($PSBoundParameters.ContainsKey('Slug'))            { $params.slug = $Slug }
    if ($PSBoundParameters.ContainsKey('CompanyId'))       { $params.company_id = $CompanyId }
    if ($PSBoundParameters.ContainsKey('Type'))            { $params.type = $Type }
    if ($PSBoundParameters.ContainsKey('ProcessScope'))    { $params.process_scope = $ProcessScope }
    if ($PSBoundParameters.ContainsKey('ParentProcessId')) { $params.parent_process_id = $ParentProcessId }
    if ($PSBoundParameters.ContainsKey('CreatedAt'))       { $params.created_at = $CreatedAt }
    if ($PSBoundParameters.ContainsKey('UpdatedAt'))       { $params.updated_at = $UpdatedAt }
    if ($PSBoundParameters.ContainsKey('Archived'))        { $params.archived = "$Archived".ToString().ToLower() }
    if ($PSBoundParameters.ContainsKey('PageSize'))        { $params.page_size = $PageSize }

    if ($PSBoundParameters.ContainsKey('GlobalTemplate')) {
        if ($PSBoundParameters.ContainsKey('ProcessScope')) {
            Write-Warning "GlobalTemplate is deprecated and was ignored because ProcessScope was also provided."
        }
        else {
            Write-Warning "GlobalTemplate is deprecated. Use -ProcessScope 'global' or 'company' instead."
            $params.type = 'process'
            switch ($GlobalTemplate.ToString().ToLowerInvariant()) {
                'true'  { $params.process_scope = 'global' }
                '1'     { $params.process_scope = 'global' }
                'false' { $params.process_scope = 'company' }
                '0'     { $params.process_scope = 'company' }
                default { Write-Warning "Unrecognized value for GlobalTemplate: '$GlobalTemplate'." }
            }
        }
    }

    if ($PSBoundParameters.ContainsKey('CompanyTemplate')) {
        if ($PSBoundParameters.ContainsKey('ProcessScope') -or $PSBoundParameters.ContainsKey('CompanyId')) {
            Write-Warning "CompanyTemplate is deprecated and was ignored because ProcessScope and/or CompanyId were also provided."
        }
        else {
            Write-Warning "CompanyTemplate is deprecated. Use -ProcessScope 'company' with -CompanyId instead."
            $params.type = 'process'
            $params.process_scope = 'company'
            $params.company_id = $CompanyTemplate
        }
    }

    if ($PSBoundParameters.ContainsKey('ParentProcedureId')) {
        if ($PSBoundParameters.ContainsKey('ParentProcessId')) {
            Write-Warning "ParentProcedureId is deprecated and was ignored because ParentProcessId was also provided."
        }
        else {
            Write-Warning "ParentProcedureId is deprecated. Use -ParentProcessId instead."
            $params.type = 'run'
            $params.parent_process_id = $ParentProcedureId
        }
    }

    Invoke-HuduRequestPaginated -HuduRequest @{
        Method   = 'GET'
        Resource = '/api/v1/procedures'
        Params   = $params
    } -Property procedures
}
#EndRegion '.\Public\Get-HuduProcedures.ps1' 114
#Region '.\Public\Get-HuduProcedureTasks.ps1' -1

function Get-HuduProcedureTasks {
    <#
    .SYNOPSIS
    Retrieve procedure tasks.
    #>
    [CmdletBinding()]
    param(
        [int]$Id,
        [int]$ProcedureId,
        [string]$Name,
        [int]$CompanyId
    )

    if ($Id) {
        try {
            $res = Invoke-HuduRequest -Method GET -Resource "/api/v1/procedure_tasks/$Id"
            return ($res.procedure_task ?? $res)
        }
        catch {
            Write-Warning "Failed to retrieve procedure task ID $Id- $($_.Exception.Message)"
            return $null
        }
    }

    $params = @{}
    if ($PSBoundParameters.ContainsKey('ProcedureId')) { $params.procedure_id = $ProcedureId }
    if ($PSBoundParameters.ContainsKey('Name'))        { $params.name = $Name }
    if ($PSBoundParameters.ContainsKey('CompanyId'))   { $params.company_id = $CompanyId }

    Invoke-HuduRequestPaginated -HuduRequest @{
        Method   = 'GET'
        Resource = '/api/v1/procedure_tasks'
        Params   = $params
    } -Property procedure_tasks
}
#EndRegion '.\Public\Get-HuduProcedureTasks.ps1' 36
#Region '.\Public\Get-HuduPublicPhotos.ps1' -1

function Get-HuduPublicPhotos {
    <#
    .SYNOPSIS
    Get a list of public photos or a single public photo, optionally downloading files.

    .DESCRIPTION
    Calls Hudu API to retrieve public photos.

    If -Download is specified with -Numeric_Id or -Id (single) or without either identifier (list), downloads public photo files using /public_photos/{numeric_id}?download=true.

    .PARAMETER Id
    Slug-based ID of the public photo to retrieve or download. Numeric values are coerced to Numeric_Id unless they are 12 digits.

    .PARAMETER Numeric_Id
    Numeric ID of the public photo to retrieve or download.

    .PARAMETER Download
    If specified, downloads public photo file(s) to OutDir.

    .PARAMETER OutDir
    Directory to download public photos into. Default current directory.

    .EXAMPLE
    Get-HuduPublicPhotos

    .EXAMPLE
    Get-HuduPublicPhotos -Id 4

    .EXAMPLE
    Get-HuduPublicPhotos -Slug 'public-photo-slug'

    .EXAMPLE
    Get-HuduPublicPhotos -Id 4 -Download

    .EXAMPLE
    Get-HuduPublicPhotos -Download -OutDir "$env:TEMP\public-photos"

    #>
    [CmdletBinding()]
    param(
        [Alias('Slug')]
        [string]$Id,
        [Alias('NumericId')]
        [Nullable[int]]$Numeric_Id,
        [switch]$Download,
        [string]$OutDir = '.'
    )

    $hasId = $PSBoundParameters.ContainsKey('Id') -and -not [string]::IsNullOrWhiteSpace($Id)
    $hasNumericId = $PSBoundParameters.ContainsKey('Numeric_Id') -and $null -ne $Numeric_Id

    if (-not $hasId -and -not $hasNumericId) {
        $HuduRequest = @{
            Method   = 'GET'
            Resource = '/api/v1/public_photos'
            Params   = @{}
        }

        $PublicPhotos = Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -Property 'public_photos'
        if (-not $Download) {
            return $PublicPhotos
        }
    }

    $numericId = $Numeric_Id
    $idText = "$Id".Trim()
    $parsedNumericId = 0
    if (
        -not $hasNumericId -and
        -not [string]::IsNullOrWhiteSpace($idText) -and
        $idText -notmatch '^\d{12}$' -and
        [int]::TryParse($idText, [ref]$parsedNumericId)
    ) {
        $numericId = $parsedNumericId
    }

    if ($null -ne $numericId) {
        $result = Invoke-HuduRequest -Method Get -Resource "/api/v1/public_photos/$numericId"
        $PublicPhotos = @($result.public_photo ?? $result)
    } elseif ($hasId) {
        $HuduRequest = @{
            Method   = 'GET'
            Resource = '/api/v1/public_photos'
            Params   = @{}
        }
        $PublicPhotos = Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -Property 'public_photos'

        $PublicPhotos = @($PublicPhotos | Where-Object { $_.id -eq $Id })
    }

    if ($Download) {
        $OutDir = if ([string]::IsNullOrWhiteSpace($OutDir)) { (Get-Location).Path } else { $OutDir }
        $OutDir = (New-Item -ItemType Directory -Path $OutDir -Force).FullName

        $Headers = @{ 'x-api-key' = (New-Object PSCredential 'user', $(Get-HuduApiKey)).GetNetworkCredential().Password }
        foreach ($p in @($PublicPhotos)) {
            $publicPhotoId = $p.numeric_id ?? $p.id
            if (-not $publicPhotoId) { continue }

            $safeName = ($p.file_name -replace '[<>:"/\\|?*\x00-\x1F]', '_')
            if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = "public-photo-$publicPhotoId" }

            $destinationPath = Join-Path -Path $OutDir -ChildPath $safeName
            $fileUrl = "$((Get-HuduBaseURL))/api/v1/public_photos/$($publicPhotoId)?download=true"

            try {
                Invoke-WebRequest -Uri $fileUrl -OutFile $destinationPath -Headers $Headers -MaximumRedirection 5 -ErrorAction Stop | Out-Null
                Write-Verbose "Downloaded '$publicPhotoId' to '$destinationPath'"
                if (Test-Path -LiteralPath $destinationPath) {
                    $p | Add-Member -MemberType NoteProperty -Name localPath -Value $destinationPath -Force
                }
            } catch {
                Write-Warning "Failed to download public photo '$publicPhotoId' from '$fileUrl': $($_.Exception.Message)"
            }
        }
    }

    $singlePublicPhoto = ($null -ne $numericId) -or $hasId
    $publicPhotosOut = $(($singlePublicPhoto ? ($PublicPhotos[0]) : $PublicPhotos))

    return $publicPhotosOut
}
#EndRegion '.\Public\Get-HuduPublicPhotos.ps1' 123
#Region '.\Public\Get-HuduRackStorageItems.ps1' -1



function Get-HuduRackStorageItems {
    <#
    .SYNOPSIS
    Provide a rack storage item id to Get a single rack storage item, otherwise Get a list of Rack Storage Items

    .DESCRIPTION
    Calls Hudu API to retrieve rack storage items with filters like asset ID, role, side, etc.

    .PARAMETER RoleId
    Filter by Rack Storage Role ID

    .PARAMETER AssetId
    Filter by Asset ID

    .PARAMETER StartUnit
    Filter by Start Unit

    .PARAMETER EndUnit
    Filter by End Unit

    .PARAMETER Status
    Filter by Status

    .PARAMETER Side
    Filter by Side (0='Front' or 1='Rear')

    .PARAMETER CreatedAfter
    Start datetime for created_at range

    .PARAMETER CreatedBefore
    End datetime for created_at range

    .PARAMETER UpdatedAfter
    Start datetime for updated_at range

    .PARAMETER UpdatedBefore
    End datetime for updated_at range
    
    .EXAMPLE
    Get-HuduRackStorageItems -RoleId 12 -Side 'Front'

    Returns all front-facing rack items associated with role ID 12.

    .NOTES
    API Endpoint: GET /api/v1/rack_storage_items
    #>
    [CmdletBinding()]
    param (
        [int]$Id,

        [int]$RoleId,
        
        [int]$AssetId,
        
        [int]$StartUnit,
        
        [int]$EndUnit,
        
        [int]$Status,
        
        [ValidateSet(0, 1)]
        [int]$Side,
        
        [datetime]$CreatedAfter,
        
        [datetime]$CreatedBefore,
        
        [datetime]$UpdatedAfter,
        
        [datetime]$UpdatedBefore
    )

    $BaseResource = "/api/v1/rack_storage_items"

    $Params = @{}
    if ($RoleId) { $Params["rack_storage_role_id"] = $RoleId }
    if ($AssetId) { $Params["asset_id"] = $AssetId }
    if ($StartUnit) { $Params["starting_unit"] = $StartUnit }
    if ($EndUnit) { $Params["end_unit"] = $EndUnit }
    if ($Status) { $Params["status"] = $Status }
    if ($Side) { $Params["side"] = $Side }

    $createdRange = Convert-ToHuduDateRange -Start $CreatedAfter -End $CreatedBefore
    if ($createdRange -ne ',' -and -$null -ne $createdRange) {
        $Params.created_at = $createdRange
    }

    $updatedRange = Convert-ToHuduDateRange -Start $UpdatedAfter -End $UpdatedBefore
    if ($updatedRange -ne ',' -and -$null -ne $updatedRange) {
        $Params.updated_at = $updatedRange
    }
    
    $HuduRequest = if ($Id) {
        @{
            Method   = 'GET'
            Resource = "$BaseResource/$Id"
        }
    } else {
        @{
            Method   = 'GET'
            Resource = "$BaseResource"
            Params   = if ($Params.Count -gt 0) { $Params } else { $null }
        }
    }

    Invoke-HuduRequest @HuduRequest
}
#EndRegion '.\Public\Get-HuduRackStorageItems.ps1' 110
#Region '.\Public\Get-HuduRackStorages.ps1' -1

function Get-HuduRackStorages {
    <#
    .SYNOPSIS
    Get a list of Rack Storages or provide ID to get a single rack storage

    .DESCRIPTION
    Calls Hudu API to retrieve rack storage items with filters like asset ID, role, side, etc.
    
    .PARAMETER Id
    ID of the Rack Storage to get

    .PARAMETER CompanyId
    Filter Rack Storages by Company Id

    .PARAMETER LocationId
    Filter Rack Storages by Location Id

    .PARAMETER Height
    Filter Rack Storages by available storage height

    .PARAMETER MaxWidth
    Filter Rack Storages by maximum available storage width

    .PARAMETER MinWidth
    Filter Rack Storages by minimum available storage width

    .PARAMETER CreatedAfter
    Start datetime for created_at range

    .PARAMETER CreatedBefore
    End datetime for created_at range

    .PARAMETER UpdatedAfter
    Start datetime for updated_at range

    .PARAMETER UpdatedBefore
    End datetime for updated_at range

    .EXAMPLE
    Get-HuduRackStorages -CompanyId 42 -MinWidth 600 -MaxWidth 800

    Returns racks for company ID 42 with widths between 600 and 800.

    .NOTES
    API Endpoint: GET /api/v1/rack_storages
    #>    
    #>    
    [CmdletBinding()]
    param (
        [int]$Id,

        [int]$CompanyId,

        [int]$LocationId,

        [int]$Height,

        [int]$MinWidth,

        [int]$MaxWidth,

        [datetime]$CreatedAfter,

        [datetime]$CreatedBefore,

        [datetime]$UpdatedAfter,

        [datetime]$UpdatedBefore
    )

    $BaseResource = "/api/v1/rack_storages"

    $Params = @{}
    if ($CompanyId)   { $Params.company_id = $CompanyId }
    if ($LocationId)  { $Params.location_id = $LocationId }
    if ($Height)      { $Params.height = $Height }
    if ($MinWidth)    { $Params.min_width = $MinWidth }
    if ($MaxWidth)    { $Params.max_width = $MaxWidth }

    $createdRange = Convert-ToHuduDateRange -Start $CreatedAfter -End $CreatedBefore
    if ($createdRange -ne ',' -and -$null -ne $createdRange) {
        $Params.created_at = $createdRange
    }

    $updatedRange = Convert-ToHuduDateRange -Start $UpdatedAfter -End $UpdatedBefore
    if ($updatedRange -ne ',' -and -$null -ne $updatedRange) {
        $Params.updated_at = $updatedRange
    }

    $HuduRequest = if ($Id) {
        @{
            Method   = 'GET'
            Resource = "$BaseResource/$Id"
        }        
    } else {
         @{
            Method   = 'GET'
            Resource = "$BaseResource"
            Params   = $Params
        }
    }

    Invoke-HuduRequest @HuduRequest
}
#EndRegion '.\Public\Get-HuduRackStorages.ps1' 105
#Region '.\Public\Get-HuduRelations.ps1' -1

function Get-HuduRelations {
    <#
    .SYNOPSIS
    Get a list of relations.

    .DESCRIPTION
    Calls the Hudu API to retrieve object relationships with optional filtering.

    .PARAMETER FromableType
    Filter by the FROM record type.

    .PARAMETER FromableId
    Filter by the FROM record ID.

    .PARAMETER ToableType
    Filter by the TO record type.

    .PARAMETER ToableId
    Filter by the TO record ID.

    .PARAMETER IsInverse
    Filter by whether the relation is the inverse side.

    .PARAMETER Description
    Filter by description.

    .PARAMETER CreatedAt
    Filter by creation date using the raw API value (YYYY-MM-DD, ISO datetime, or API-supported range string).

    .PARAMETER CreatedAfter
    Start datetime for the created_at range.

    .PARAMETER CreatedBefore
    End datetime for the created_at range.

    .PARAMETER UpdatedAt
    Filter by update date using the raw API value (YYYY-MM-DD, ISO datetime, or API-supported range string).

    .PARAMETER UpdatedAfter
    Start datetime for the updated_at range.

    .PARAMETER UpdatedBefore
    End datetime for the updated_at range.

    .PARAMETER Page
    Return a specific page instead of auto-paginating all results.

    .PARAMETER PageSize
    Number of results per page. Defaults to 1000 when auto-paginating.

    .EXAMPLE
    Get-HuduRelations -FromableType Asset -FromableId 123

    .EXAMPLE
    Get-HuduRelations -ToableType Company -ToableId 42 -IsInverse $false

    .EXAMPLE
    Get-HuduRelations -CreatedAfter ([datetime]'2026-08-01') -UpdatedBefore ([datetime]'2026-08-07')

    #>
    [CmdletBinding()]
    Param(
        [Alias('fromable_type')]
        [ValidateScript({ Assert-AllowedObjectType -InputType $_ -AllowedCanonicals @(
            'Asset', 'Website', 'Procedure', 'AssetPassword', 'Company', 'Article', 'Network', 'IpAddress', 'Vlan', 'VlanZone', 'RackStorage'
        ) })]
        [string]$FromableType,

        [Alias('fromable_id')]
        [int]$FromableId,

        [Alias('toable_type')]
        [ValidateScript({ Assert-AllowedObjectType -InputType $_ -AllowedCanonicals @(
            'Asset', 'Website', 'Procedure', 'AssetPassword', 'Company', 'Article', 'Network', 'IpAddress', 'Vlan', 'VlanZone', 'RackStorage'
        ) })]
        [string]$ToableType,

        [Alias('toable_id')]
        [int]$ToableId,

        [Alias('is_inverse')]
        [bool]$IsInverse,

        [string]$Description,

        [Alias('created_at')]
        [string]$CreatedAt,

        [datetime]$CreatedAfter,
        [datetime]$CreatedBefore,

        [Alias('updated_at')]
        [string]$UpdatedAt,

        [datetime]$UpdatedAfter,
        [datetime]$UpdatedBefore,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$Page,

        [Alias('page_size')]
        [ValidateRange(1, 1000)]
        [int]$PageSize = 1000
    )

    if ($PSBoundParameters.ContainsKey('CreatedAt') -and ($PSBoundParameters.ContainsKey('CreatedAfter') -or $PSBoundParameters.ContainsKey('CreatedBefore'))) {
        throw "Use either -CreatedAt or -CreatedAfter/-CreatedBefore, not both."
    }

    if ($PSBoundParameters.ContainsKey('UpdatedAt') -and ($PSBoundParameters.ContainsKey('UpdatedAfter') -or $PSBoundParameters.ContainsKey('UpdatedBefore'))) {
        throw "Use either -UpdatedAt or -UpdatedAfter/-UpdatedBefore, not both."
    }

    $params = @{}

    if ($PSBoundParameters.ContainsKey('FromableType')) { $params.fromable_type = Get-ObjectTypeFromCononical -inputData $FromableType }
    if ($PSBoundParameters.ContainsKey('FromableId'))   { $params.fromable_id   = $FromableId }
    if ($PSBoundParameters.ContainsKey('ToableType'))   { $params.toable_type   = Get-ObjectTypeFromCononical -inputData $ToableType }
    if ($PSBoundParameters.ContainsKey('ToableId'))     { $params.toable_id     = $ToableId }
    if ($PSBoundParameters.ContainsKey('IsInverse'))    { $params.is_inverse    = $IsInverse.ToString().ToLowerInvariant() }
    if ($PSBoundParameters.ContainsKey('Description'))  { $params.description   = $Description }
    if ($PSBoundParameters.ContainsKey('CreatedAt'))    { $params.created_at    = $CreatedAt }
    if ($PSBoundParameters.ContainsKey('UpdatedAt'))    { $params.updated_at    = $UpdatedAt }

    $createdRange = Convert-ToHuduDateRange -Start $CreatedAfter -End $CreatedBefore
    if ($null -ne $createdRange) {
        $params.created_at = $createdRange
    }

    $updatedRange = Convert-ToHuduDateRange -Start $UpdatedAfter -End $UpdatedBefore
    if ($null -ne $updatedRange) {
        $params.updated_at = $updatedRange
    }

    $HuduRequest = @{
        Method   = 'GET'
        Resource = '/api/v1/relations'
        Params   = $params
    }

    if ($PSBoundParameters.ContainsKey('Page')) {
        $params.page = $Page
        $params.page_size = $PageSize
        $response = Invoke-HuduRequest @HuduRequest
        return ($response.relations ?? $response)
    }

    Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -Property 'relations' -PageSize $PageSize
}
#EndRegion '.\Public\Get-HuduRelations.ps1' 150
#Region '.\Public\Get-HuduUploads.ps1' -1

function Get-HuduUploads {
    <#
    .SYNOPSIS
    Get a list of uploads

    .DESCRIPTION
    Calls Hudu API to retrieve uploads

    .PARAMETER Id
    ID of the Upload to retrieve or Download (Hudu 2.41.0+)

    .PARAMETER OutDir
    Directory to download uploads to. Used only with -Download (Hudu 2.41.0+). Defaults to current directory.

    .EXAMPLE
    Get-HuduUploads

    #>
    [CmdletBinding()]
    param(
        [int]$Id,
        [switch]$Download,
        [string]$OutDir = '.'
    )

    [version]$script:Version = $script:Version ?? [version]((Get-HuduAppInfo).version)

    $Upload = @()
    if ($Id) {
        $Upload = Invoke-HuduRequest -Method Get -Resource "/api/v1/uploads/$Id"
    } else {
        if ($script:Version -lt [version]'2.41.0') {
            $Upload = Invoke-HuduRequest -Method Get -Resource "/api/v1/uploads"
        } else {
            $Upload = Invoke-HuduRequestPaginated -hudurequest @{ Method = 'Get'; Resource = '/api/v1/uploads'; params = @{}}
        }
    }

    if ($Download) {
        if ($script:Version -lt [version]'2.41.0') {
            Write-Warning "Download of uploads is only supported in Hudu v2.41.0 and above; skipping download."
        } else {
            $OutDir = if ([string]::IsNullOrWhiteSpace($OutDir)) { (Get-Location).Path } else { $OutDir }
            $OutDir = (New-Item -ItemType Directory -Path $OutDir -Force).FullName

            $Headers = @{ 'x-api-key' = (New-Object PSCredential 'user', $(Get-HuduApiKey)).GetNetworkCredential().Password }
            foreach ($u in @($Upload)) {
                if (-not $u.id -or $u.id -lt 1){continue}
                $safeName = ($u.name -replace '[<>:"/\\|?*\x00-\x1F]', '_')
                if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = "upload-$($u.id)" }

                $destinationPath = Join-Path -Path $OutDir -ChildPath $safeName

                $fileUrl = "$($script:Int_HuduBaseURL)/api/v1/uploads/$($u.id)?download=true"

                try {
                    Invoke-WebRequest -Uri $fileUrl -OutFile $destinationPath -Headers $Headers -MaximumRedirection 3 -ErrorAction Stop | Out-Null
                    Write-Verbose "Downloaded '$($u.name)' to '$destinationPath'"
                    if (Test-Path -LiteralPath $destinationPath) {
                        $u | Add-Member -MemberType NoteProperty -Name localPath -Value $destinationPath -Force
                    }
                } catch {
                    Write-Warning "Failed to download '$($u.name)' from '$fileUrl': $($_.Exception.Message)"
                }
            }
        }
    }

    return $Upload
}
#EndRegion '.\Public\Get-HuduUploads.ps1' 71
#Region '.\Public\Get-HuduUsers.ps1' -1

function Get-HuduUsers {
    <#
    .SYNOPSIS
    Get a list of Users

    .DESCRIPTION
    Call Hudu API to retrieve Users

    .PARAMETER Id
    Id of requested users

    .PARAMETER Users
    Name of the requested user

    .PARAMETER CompanyId
    Id of the requested company

    .PARAMETER Name
    Filter by name

    .PARAMETER Archived
    Show archived results

    .PARAMETER Slug
    Filter by slug of user

    .EXAMPLE
    Get-HuduUsers -Name 'Jim'
#>

[CmdletBinding()]
    Param (
        [ValidateRange(1, [int]::MaxValue)]
        [Int]$Id = '',
        [string]$Email = '',
        [string]$First_name = '',
        [string]$Last_name = '',
	    [ValidateRange(1, [int]::MaxValue)]
        [Int]$Portal_member_company_id = '',
	    [String]$Securitylevel = '',
        [string]$Slug = ''
    )

    if ($Id) {
        Invoke-HuduRequest -Method get -Resource "/api/v1/users/$Id"
    } else {
        $Params = @{}

        if ($First_name) { $Params.first_name = $First_name}
        if ($Last_name) { $Params.last_name = $Last_name}
        if ($Email) { $Params.email = $Email}

        $HuduRequest = @{
            Method   = 'GET'
            Resource = '/api/v1/users'
            Params   = $Params
    }

        Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -Property Users
    }
}
#EndRegion '.\Public\Get-HuduUsers.ps1' 62
#Region '.\Public\Get-HuduVLANs.ps1' -1

function Get-HuduVLANs {
<#
.SYNOPSIS
Retrieve VLAN records from Hudu.

.DESCRIPTION
Queries the Hudu API for VLANs. Supports filtering by Id, VLAN Id, VLAN Zone association, company, slug, 
name, archival status, or creation/update timestamps.

.PARAMETER Id
Specific VLAN Id.

.PARAMETER VLANId
Filter by VLAN Id (must be between 4 and 4094).

.PARAMETER VLANZoneID
Filter by associated VLAN Zone Id.

.PARAMETER CompanyId
Filter by company identifier.

.PARAMETER Slug
Filter by slug value.

.PARAMETER Name
Filter by VLAN name.

.PARAMETER Archived
Filter by archival status: "true" or "false".

.PARAMETER CreatedAfter
Return VLANs created after this date/time.

.PARAMETER CreatedBefore
Return VLANs created before this date/time.

.PARAMETER UpdatedAfter
Return VLANs updated after this date/time.

.PARAMETER UpdatedBefore
Return VLANs updated before this date/time.

.EXAMPLE
Get-HuduVLANs -CompanyId 5 -Archived "false"
#>    
    [CmdletBinding()]
    param(
        [int]$Id,
        [ValidateRange(4,4094)][int]$VLANId,
        [int]$VLANZoneID,
        [int]$CompanyId,
        [string]$Slug,
        [string]$Name,
        [string]$Archived,
        [datetime]$CreatedAfter,
        [datetime]$CreatedBefore,
        [datetime]$UpdatedAfter,
        [datetime]$UpdatedBefore        
    )

    if ($Id) {
        try {
            $res = Invoke-HuduRequest -Method GET -Resource "/api/v1/vlans/$Id"
            return $res
        } catch {
            Write-Warning "Failed to retrieve vlan ID $Id"
            return $null
        }
    }

    $params = @{}
    if ($VLANId)            { $params.vlan_id      = $VLANId }
    if ($VLANZoneID)        { $params.vlan_zone_id = $VLANZoneID }
    if ($CompanyId)         { $params.company_id   = $CompanyId }
    if ($Slug)              { $params.slug         = $Slug }
    if ($Name)              { $params.name         = $Name }
    if ($Archived)          { $params.archived     = $Archived }

    $createdRange = Convert-ToHuduDateRange -Start $CreatedAfter -End $CreatedBefore
    if ($createdRange -ne ',' -and -$null -ne $createdRange) {
        $params.created_at = $createdRange
    }

    $updatedRange = Convert-ToHuduDateRange -Start $UpdatedAfter -End $UpdatedBefore
    if ($updatedRange -ne ',' -and -$null -ne $updatedRange) {
        $params.updated_at = $updatedRange
    }
    if ($params) {
        Invoke-HuduRequest -Method GET -Resource '/api/v1/vlans' -Params $params
    } else {
        Invoke-HuduRequest -Method GET -Resource "/api/v1/vlans"    
    }
}
#EndRegion '.\Public\Get-HuduVLANs.ps1' 94
#Region '.\Public\Get-HuduVLANZones.ps1' -1

function Get-HuduVLANZones {
<#
.SYNOPSIS
Retrieve VLAN Zone records from Hudu.

.DESCRIPTION
Queries the Hudu API for VLAN Zones. Can filter by Id, CompanyId, Name, VLAN ranges, or archival status, 
as well as created/updated date ranges.

.PARAMETER Id
Specific VLAN Zone Id.

.PARAMETER CompanyId
Filter by company identifier.

.PARAMETER Name
Filter by name (string match).

.PARAMETER Archived
Filter by archival status: "true" or "false".

.PARAMETER VLANIdRanges
Filter by VLAN Id ranges (e.g. "1-4", "200-300,400-450").

.PARAMETER CreatedAfter
Return only VLAN Zones created after this date/time.

.PARAMETER CreatedBefore
Return only VLAN Zones created before this date/time.

.PARAMETER UpdatedAfter
Return only VLAN Zones updated after this date/time.

.PARAMETER UpdatedBefore
Return only VLAN Zones updated before this date/time.

.EXAMPLE
Get-HuduVLANZones -CompanyId 5 -Archived "false"
#>    
    [CmdletBinding()]
    param(
        [int]$Id,
        [int]$CompanyId,
        [string]$Name,
        [string]$Archived,
        # VLAN ranges: "1-4", "200-300,400-450", etc.
        [ValidatePattern('^([1-9][0-9]{0,3}-[1-9][0-9]{0,3})(,([1-9][0-9]{0,3}-[1-9][0-9]{0,3}))*$')]
        [string]$VLANIdRanges,
        [datetime]$CreatedAfter,
        [datetime]$CreatedBefore,
        [datetime]$UpdatedAfter,
        [datetime]$UpdatedBefore        
    )

    if ($Id) {
        try {
            $res = Invoke-HuduRequest -Method GET -Resource "/api/v1/vlan_zones/$Id"
            return $res
        } catch {
            Write-Warning "Failed to retrieve vlan zone ID $Id"
            return $null
        }
    }

    $params = @{}
    if ($CompanyId)         { $params.company_id   = $CompanyId }
    if ($Name)              { $params.name         = $Name }
    if ($Archived)          { $params.archived     = $Archived }

    $createdRange = Convert-ToHuduDateRange -Start $CreatedAfter -End $CreatedBefore
    if ($createdRange -ne ',' -and -$null -ne $createdRange) {
        $params.created_at = $createdRange
    }

    $updatedRange = Convert-ToHuduDateRange -Start $UpdatedAfter -End $UpdatedBefore
    if ($updatedRange -ne ',' -and -$null -ne $updatedRange) {
        $params.updated_at = $updatedRange
    }
    if ($params){
        Invoke-HuduRequest -Method GET -Resource '/api/v1/vlan_zones' -Params $params
    } else {
        Invoke-HuduRequest -Method GET -Resource '/api/v1/vlan_zones'
    }
}
#EndRegion '.\Public\Get-HuduVLANZones.ps1' 85
#Region '.\Public\Get-HuduWebsites.ps1' -1

function Get-HuduWebsites {
    <#
	.SYNOPSIS
	Get a list of all websites

	.DESCRIPTION
	Calls Hudu API to get websites

	.PARAMETER Name
	Filter websites by name

	.PARAMETER Id
	ID of website

	.PARAMETER Slug
	Filter by url slug

    .PARAMETER Search
    Fitler by search query

    .PARAMETER UpdatedAfter
    Get Websites Refreshed or Monitored After X datetime
    
    .PARAMETER UpdatedBefore
    Get Websites Refreshed or Monitored Before Y datetime

	.EXAMPLE
	Get-HuduWebsites -Search 'domain.com'
    Get-HuduWebsites -UpdatedAfter $(get-date).AddMinutes(-12)
    Get-HuduWebsites -UpdatedBefore $(get-date).AddDays(-7)

	#>
    [CmdletBinding()]
    Param (
        [String]$Name,
        [Alias('website_id','Id')]
        [Int]$WebsiteId,
        [String]$Slug,
        [string]$Search,
        [datetime]$UpdatedAfter,
        [datetime]$UpdatedBefore
    )

    if ($WebsiteId) {
        Invoke-HuduRequest -Method get -Resource "/api/v1/websites/$($WebsiteId)"
    } else {
        $Params = @{}
        if ($Name) { $Params.name = $Name }
        if ($Slug) { $Params.slug = $Slug }
        if ($Search) { $Params.search = $Search }
        $updatedRange = Convert-ToHuduDateRange -Start $UpdatedAfter -End $UpdatedBefore
        if ($updatedRange -ne ',' -and -$null -ne $updatedRange) {
            $Params.updated_at = $updatedRange
        }
        $HuduRequest = @{
            Method   = 'GET'
            Resource = '/api/v1/websites'
            Params   = $Params
        }
        Invoke-HuduRequestPaginated -HuduRequest $HuduRequest
    }
}
#EndRegion '.\Public\Get-HuduWebsites.ps1' 63
#Region '.\Public\Initialize-HuduFolder.ps1' -1

function Initialize-HuduFolder {
    [CmdletBinding()]
    param(
        [String[]]$FolderPath,
        [Alias('company_id')]
        [Nullable[int]]$CompanyId
    )

    if ($null -ne $CompanyId) {
        $FolderMap = Get-HuduFolderMap -company_id $CompanyId
    } else {
        $FolderMap = Get-HuduFolderMap
    }

    $CurrentFolder = $FolderMap
    foreach ($Folder in $FolderPath) {
        if ($CurrentFolder.$(Get-HuduFolderCleanName $Folder)) {
            $CurrentFolder = $CurrentFolder.$(Get-HuduFolderCleanName $Folder)
        } else {
            $NewFolderParams = @{
                Name = $Folder
            }

            if ($null -ne $CompanyId) {
                $NewFolderParams.CompanyId = $CompanyId
            }

            if ($null -ne $CurrentFolder.id) {
                $NewFolderParams.ParentFolderId = $CurrentFolder.id
            }

            $CurrentFolder = (New-HuduFolder @NewFolderParams).folder
        }
    }

    return $CurrentFolder
}
#EndRegion '.\Public\Initialize-HuduFolder.ps1' 38
#Region '.\Public\Move-HuduArticleCompany.ps1' -1

function Move-HuduArticleCompany {
    <#
    .SYNOPSIS
    Move a Knowledge Base Article to a different company

    .DESCRIPTION
    Uses Hudu API to update an article's company_id via PUT /api/v1/articles/{id}

    .PARAMETER ArticleId
    Id of the article to move

    .PARAMETER CompanyId
    Destination company id. Use $null to move the article to the central Knowledge Base.

    .PARAMETER FolderId
    Optional destination-company folder id. When omitted, the article is moved
    to the root of the destination company's Knowledge Base.

    .EXAMPLE
    Move-HuduArticleCompany -ArticleId 1 -CompanyId 20

    .EXAMPLE
    Move-HuduArticleCompany -ArticleId 1 -CompanyId $null # moves to central kb

    .EXAMPLE
    Move-HuduArticleCompany -ArticleId 1 -CompanyId 20 -FolderId 5
    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (

        [Alias('article_id', 'id')]
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, [int]::MaxValue)]
        [Int]$ArticleId,

        [Alias('company_id','new_company_id','destination_company_id','target_company_id')]
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [Nullable[int]]$CompanyId,

        [Alias('folder_id')]
        [ValidateRange(1, [int]::MaxValue)]
        [Nullable[int]]$FolderId
    )

    if ($null -ne $CompanyId -and $CompanyId -lt 1) {
        throw "CompanyId must be a positive integer, or `$null for the central Knowledge Base."
    }

    $DestinationDescription = if ($null -eq $CompanyId) { 'central Knowledge Base' } else { "company $CompanyId" }

    $DestinationFolderId = $null
    if ($PSBoundParameters.ContainsKey('FolderId')) {
        $Folder = Get-HuduFolders -Id $FolderId
        if (-not $Folder) {
            throw "Destination folder $FolderId could not be found."
        }
        $FolderCompanyId = if ($null -eq $Folder.company_id) { $null } else { [int]$Folder.company_id }
        if ($FolderCompanyId -ne $CompanyId) {
            throw "Destination folder $FolderId does not belong to $DestinationDescription."
        }
        $DestinationFolderId = $FolderId
    }

    # Hudu rejects a company change while folder_id still references a folder
    # owned by the source company. Explicitly clear it unless a validated
    # destination-company folder was supplied.
    $Article = [ordered]@{
        article = [ordered]@{
            company_id = $CompanyId
            folder_id  = $DestinationFolderId
        }
    }
    $JSON = $Article | ConvertTo-Json -Depth 10

    if ($PSCmdlet.ShouldProcess("Article ID: $ArticleId", "Move to $DestinationDescription")) {
        $Result = Invoke-HuduRequest -Method put -Resource "/api/v1/articles/$ArticleId" -Body $JSON

        # Invoke-HuduRequest returns $null after a failed retry, so verify the
        # persisted state instead of silently reporting a successful move.
        $VerificationResponse = Get-HuduArticles -Id $ArticleId
        $MovedArticle = $VerificationResponse.article
        if (-not $MovedArticle) {
            $MovedArticle = $VerificationResponse
        }

        $MovedCompanyId = if ($MovedArticle -and $null -eq $MovedArticle.company_id) { $null } elseif ($MovedArticle) { [int]$MovedArticle.company_id }
        if (-not $MovedArticle -or $MovedCompanyId -ne $CompanyId) {
            throw "Article $ArticleId did not move to $DestinationDescription."
        }
        if ($null -eq $DestinationFolderId) {
            if ($null -ne $MovedArticle.folder_id) {
                throw "Article $ArticleId moved to $DestinationDescription but folder_id was not cleared."
            }
        } elseif ([int]$MovedArticle.folder_id -ne $DestinationFolderId) {
            throw "Article $ArticleId moved to $DestinationDescription but not to folder $DestinationFolderId."
        }

        if ($null -ne $Result) {
            $Result
        } else {
            $MovedArticle
        }
    }
}
#EndRegion '.\Public\Move-HuduArticleCompany.ps1' 106
#Region '.\Public\Move-HuduAssetCompany.ps1' -1

function Move-HuduAssetCompany {
    <#
    .SYNOPSIS
    Move an Asset to a different company

    .DESCRIPTION
    Uses Hudu API to update an asset's company_id via PUT /api/v1/companies/{company_id}/assets/{id}

    The company in the URL identifies the asset, so it must be the company that
    currently owns it. That id is looked up from the asset itself; CompanyId is
    the destination and is sent in the body.

    .PARAMETER AssetId
    Id of the asset to move

    .PARAMETER CompanyId
    Destination company id

    .EXAMPLE
    Move-HuduAssetCompany -AssetId 1 -CompanyId 20

    .EXAMPLE
    Move-HuduAssetCompany -AssetId 1 -CompanyId 44
    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Alias('asset_id', 'id')]
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, [int]::MaxValue)]
        [Int]$AssetId,

        [Alias('company_id','new_company_id','destination_company_id','target_company_id')]
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, [int]::MaxValue)]
        [Int]$CompanyId
    )

    # Get-HuduAssets -Id alone queries the collection endpoint, so take the single match rather than letting an array land in the request URL.
    $Object = Get-HuduAssets -Id $AssetId | Select-Object -First 1
    if (-not $Object) {
        throw "A valid asset could not be found to move, please double check the ID and try again"
    }

    $CurrentCompanyId = $Object.company_id
    $Asset = [ordered]@{asset = [ordered]@{company_id = $CompanyId } }
    $JSON = $Asset | ConvertTo-Json -Depth 10

    if ($PSCmdlet.ShouldProcess("ID: $AssetId Name: $($Object.name)", "Move Asset from company $CurrentCompanyId to $CompanyId")) {
        Invoke-HuduRequest -Method put -Resource "/api/v1/companies/$CurrentCompanyId/assets/$AssetId" -Body $JSON
    }
}
#EndRegion '.\Public\Move-HuduAssetCompany.ps1' 52
#Region '.\Public\Move-HuduAssetsToNewLayout.ps1' -1

function Move-HuduAssetsToNewLayout {
    <#
    .SYNOPSIS
    Moves an Asset between two Asset Layouts

    .DESCRIPTION
    Uses Hudu API to move an Asset from one Asset Layout to another
    
    .PARAMETER CompanyId
    Company id of the Asset

    .PARAMETER AssetLayoutId
    New Asset layout id where the asset will be moved to

    .PARAMETER AssetId
    Id of the Asset to move
    
    .EXAMPLE
    Move-HuduAssetsToNewLayout -AssetId 5 -CompanyId 1 -AssetLayoutId 5

    .NOTES
    General notes
    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [String]$Name,

        [Alias('company_id')]
        [Int]$CompanyId,

        [Alias('asset_layout_id')]
        [Int]$AssetLayoutId,

        [Alias('asset_id','assetid')]
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, [int]::MaxValue)]
        [Int]$Id
    )
    
    $Object = Get-HuduAssets -id $Id | Select-Object name,asset_layout_id,company_id,slug,primary_serial,primary_model,primary_mail,id,primary_manufacturer,@{n='custom_fields';e={$_.fields | ForEach-Object {[pscustomobject]@{$_.label.replace(' ','_').tolower()= $_.value}}}}
    if ($Object) {
        $Asset = [pscustomobject]@{asset_layout_id = $AssetLayoutId}
    
    
        $JSON = $Asset | ConvertTo-Json -Depth 10
    
        if ($PSCmdlet.ShouldProcess("ID: $($Asset.id) Name: $($Asset.Name)", "Move Asset from Layout $($Object.asset_layout_id) to $($AssetLayoutId)")) {
            Invoke-HuduRequest -Method put -Resource "/api/v1/companies/$CompanyId/assets/$Id/move_layout" -Body $JSON
        }
    } else {
    throw "A valid asset could not be found to update, please double check the ID and try again"
    }
}
#EndRegion '.\Public\Move-HuduAssetsToNewLayout.ps1' 54
#Region '.\Public\Move-HuduAssetsToNewLayoutDeprecated.ps1' -1

function Move-HuduAssetsToNewLayout {
<#
    .SYNOPSIS
    Helper function that uses the Set-HuduAsset function to move an asset between asset layouts. This will leave behind orphan data in the database.
    Review the article https://portal.risingtidegroup.net/kb?id=29 for more details.

    .DESCRIPTION
    Calls the Hudu API to update an asset by switching its asset_layout_id property to a different asset layout. 
    This function migrates the asset to the specified new layout while maintaining its fields. Note that this 
    operation may leave behind orphaned data in the Hudu database, so use it with caution.

    .PARAMETER AssetsToMove
    An array of assets to be moved to a new asset layout. Each asset must contain both 'id' and 'fields' properties.

    .PARAMETER NewAssetLayoutID
    The ID of the new asset layout to which the assets will be moved.

    .EXAMPLE
    $AssetLayout = Get-HuduAssetLayouts -Name "Servers"
    $AssetsToUpdate = Get-HuduAssets -AssetLayoutId 9
    Move-HuduAssetsToNewLayout -AssetsToMove $AssetsToUpdate -NewAssetLayoutID $AssetLayout.id

    This example retrieves the asset layout with the name "Servers" and the assets with the layout ID 9, then moves those assets to the new layout.

    .NOTES
    Ensure that the new asset layout ID is valid and that the assets to be moved contain the required properties.
    Using this function may result in orphaned data in your Hudu database. Review the provided article for more details.
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                if ($BadAssets = ($_ | where {(-not $_.id)})) {
                    $BadAssets
                    throw "Assets must be an object with an ID"
                }
            return $true
        })]
        [array]
        $AssetsToMove,

        [Parameter(Mandatory = $true)]
        [int]
        $NewAssetLayoutID
    )

    Write-Warning "Performing this function will leave behind orphaned data in your Hudu database. Please review https://portal.risingtidegroup.net/kb?id=29"
    Read-Host "Press Enter to continue or (CTRL+C) to cancel..."

    $assets = foreach ($AssetToMove in $AssetsToMove) {
        if (-not ($AssetToMove.PSObject.Properties.Match('id')) -or -not ($AssetToMove.PSObject.Properties.Match('fields'))) {
            Write-Error "Asset does not contain both 'id' and 'fields' properties. Skipping this asset."
            continue
        }

        if (-not $AssetToMove.fields) {
            Write-Warning "Asset ID: $($AssetToMove.id) has no fields. Proceeding with moving the asset."
        }

        $assetId = $AssetToMove.id

        if ($PSCmdlet.ShouldProcess("Asset ID: $assetId", "Move to new layout with ID $NewAssetLayoutID")) {
            try {
                Write-Verbose "Processing Asset ID: $assetId"

                $fields = New-Object -TypeName psobject
                foreach ($field in $AssetToMove.fields) {
                    $fieldName = $field.label.replace(' ', '_').tolower()
                    $fields | Add-Member -MemberType NoteProperty -Name $fieldName -Value $field.value -Force
                }

                (Set-HuduAsset -Id $assetId -AssetLayoutId $NewAssetLayoutID -Fields $fields).asset

                Write-Verbose "Successfully moved Asset ID: $assetId"
            }
            catch {
                Write-Error "Failed to move Asset ID: $assetId. Error: $_"
            }
            finally {
                Remove-Variable -Name fields -ErrorAction SilentlyContinue
            }
        }
    }
    return $assets
}
#EndRegion '.\Public\Move-HuduAssetsToNewLayoutDeprecated.ps1' 87
#Region '.\Public\New-HuduAPIKey.ps1' -1

function New-HuduAPIKey {
    <#
    .SYNOPSIS
    Set Hudu API Key

    .DESCRIPTION
    API keys are required to interact with Hudu

    .PARAMETER ApiKey
    The API key

    .EXAMPLE
    New-HuduAPIKey -ApiKey abdc1234

    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Scope = 'Function')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Scope = 'Function')]
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [String]$ApiKey
    )

    process {
        if ($ApiKey) {
            $SecApiKey = ConvertTo-SecureString $ApiKey -AsPlainText -Force
        } else {
            $SecApiKey = Read-Host -Prompt 'Please enter your Hudu API key, you can obtain it from https://your-hudu-domain/admin/api_keys:' -AsSecureString
        }
        Set-Variable -Name 'Int_HuduAPIKey' -Value $SecApiKey -Visibility Private -Scope script -Force

        if ($script:Int_HuduBaseURL) {
            [version]$script:Version = (Get-HuduAppInfo).version
            if ($script:Version -lt $script:HuduRequiredVersion) {
                Write-Warning "A connection error occured or Hudu version $($script:Version ?? "unknown") is below $script:HuduRequiredVersion"
            }
        }
    }
}
#EndRegion '.\Public\New-HuduAPIKey.ps1' 40
#Region '.\Public\New-HuduArticle.ps1' -1

function New-HuduArticle {
    <#
    .SYNOPSIS
    Create a Knowledge Base Article

    .DESCRIPTION
    Uses Hudu API to create KB articles

    .PARAMETER Name
    Name of article

    .PARAMETER Content
    Article HTML contents

    .PARAMETER EnableSharing
    Create public URL for users to view without being authenticated

    .PARAMETER FolderId
    Associate article with folder id

    .PARAMETER CompanyId
    Associate article with company id

    .PARAMETER Slug
    Manually define slug for Article

    .EXAMPLE
    New-HuduArticle -Name "Test" -CompanyId 1 -Content '<h1>Testing</h1>' -EnableSharing -Slug 'this-is-a-test'

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [String]$Name,

        [Parameter(Mandatory = $true)]
        [String]$Content,

        [switch]$EnableSharing,

        [Alias('folder_id')]
        [Int]$FolderId = '',

        [Alias('company_id')]
        [Int]$CompanyId = '',

        [string]$Slug
    )

    $Article = [ordered]@{article = [ordered]@{} }

    $Article.article.add('name', $Name)
    $Article.article.add('content', $Content)

    if ($FolderId) {
        $Article.article.add('folder_id', $FolderId)
    }

    if ($CompanyId) {
        $Article.article.add('company_id', $CompanyId)
    }

    if ($EnableSharing.IsPresent) {
        $Article.article.add('enable_sharing', 'true')
    }

    if ($Slug) {
        $Article.article.add('slug', $Slug)
    }

    $JSON = $Article | ConvertTo-Json -Depth 10

    if ($PSCmdlet.ShouldProcess($Name)) {
        Invoke-HuduRequest -Method post -Resource '/api/v1/articles' -Body $JSON
    }
}
#EndRegion '.\Public\New-HuduArticle.ps1' 77
#Region '.\Public\New-HuduAsset.ps1' -1

function New-HuduAsset {
    <#
    .SYNOPSIS
    Create an Asset

    .DESCRIPTION
    Uses Hudu API to create assets using custom layouts

    .PARAMETER Name
    Name of the Asset

    .PARAMETER CompanyId
    Company id for asset

    .PARAMETER AssetLayoutId
    Asset layout id

    .PARAMETER Fields
    Array of custom fields and values

    .PARAMETER PrimarySerial
    Asset primary serial number

    .PARAMETER PrimaryMail
    Asset primary mail

    .PARAMETER PrimaryModel
    Asset primary model

    .PARAMETER PrimaryManufacturer
    Asset primary manufacturer

    .PARAMETER Slug
    Url identifier

    .EXAMPLE
    New-HuduAsset -Name 'Some asset' -CompanyId 1 -Fields @(@{'field_name'='Field Value'})

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [String]$Name,

        [Alias('company_id')]
        [Parameter(Mandatory = $true)]
        [Int]$CompanyId,

        [Alias('asset_layout_id')]
        [Parameter(Mandatory = $true)]
        [Int]$AssetLayoutId,

        [Array]$Fields,

        [Alias('primary_serial')]
        [string]$PrimarySerial,

        [Alias('primary_mail')]
        [string]$PrimaryMail,

        [Alias('primary_model')]
        [string]$PrimaryModel,

        [Alias('primary_manufacturer')]
        [string]$PrimaryManufacturer
    )

    $Asset = [ordered]@{asset = [ordered]@{} }

    $Asset.asset.add('name', $Name)
    $Asset.asset.add('asset_layout_id', $AssetLayoutId)


    if ($PrimarySerial) {
        $Asset.asset.add('primary_serial', $PrimarySerial)
    }

    if ($PrimaryMail) {
        $Asset.asset.add('primary_mail', $PrimaryMail)
    }

    if ($PrimaryModel) {
        $Asset.asset.add('primary_model', $PrimaryModel)
    }

    if ($PrimaryManufacturer) {
        $Asset.asset.add('primary_manufacturer', $PrimaryManufacturer)
    }

    if ($Fields) {
        $Asset.asset.add('custom_fields', $Fields)
    }

    if ($Slug) {
        $Asset.asset.add('slug', $Slug)
    }

    $JSON = $Asset | ConvertTo-Json -Depth 10

    if ($PSCmdlet.ShouldProcess($Name)) {
        Invoke-HuduRequest -Method post -Resource "/api/v1/companies/$CompanyId/assets" -Body $JSON
    }
}
#EndRegion '.\Public\New-HuduAsset.ps1' 104
#Region '.\Public\New-HuduAssetLayout.ps1' -1

function New-HuduAssetLayout {
    <#
    .SYNOPSIS
    Create an Asset Layout

    .DESCRIPTION
    Uses Hudu API to create new custom asset layout

    .PARAMETER Name
    Name of the layout

    .PARAMETER Icon
    FontAwesome Icon class name, example: "fas fa-home"

    .PARAMETER Color
    Background color as a hex value, such as #ff0000, or a human-readable color
    name in a supported language. Alpha values are trimmed off.

    .PARAMETER IconColor
    Icon color as a hex value, such as #ff0000, or a human-readable color
    name in a supported language. Alpha values are trimmed off.

    .PARAMETER IncludePasswords
    Boolean for including passwords

    .PARAMETER IncludePhotos
    Boolean for including photos

    .PARAMETER IncludeComments
    Boolean for including comments

    .PARAMETER IncludeFiles
    Boolean for including files

    .PARAMETER PasswordTypes
    List of password types, separated with new line characters

    .PARAMETER Slug
    Url identifier

    .PARAMETER Fields
    Array of hashtable or custom objects representing layout fields. Most field types only require a label and type.
    Valid field types are: Text, RichText, Heading, CheckBox, Website (aka Link), Password (aka ConfidentialText), Number, Date, DropDown (deprecated), ListSelect (replacement for Dropdown), Embed, Email (aka CopyableText), Phone, AssetLink
    Field types are Case Sensitive as of Hudu V2.27 due to a known issue with asset type validation.

    .EXAMPLE
    New-HuduAssetLayout -Name 'Test asset layout' -Icon 'fas fa-home' -IncludePassword $true

    .EXAMPLE
    New-HuduAssetLayout -Name 'Routers' -Icon 'fas fa-network-wired' -Color 'azul' -IconColor '#ffffff' -Fields @(
        @{label = 'Hostname'; 'field_type' = 'Text'}
    )

    .EXAMPLE
    New-HuduAssetLayout -Name 'Routers' -Icon 'fas fa-network-wired' -Color 'azul' -IconColor '#ffffff' -SidebarFolderID 3 -Fields @(
        @{label = 'Hostname'; 'field_type' = 'Text'}
    )

    .EXAMPLE
    New-HuduAssetLayout -Name 'Test asset layout' -Icon 'fas fa-home' -IncludePassword $true -Fields @(
        @{label = 'Test field'; 'field_type' = 'Text'}
    )
    #>
    [CmdletBinding(SupportsShouldProcess)]
    # This will silence the warning for variables with Password in their name.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '')]
    Param (
        [Parameter(Mandatory = $true)]
        [String]$Name,

        [Parameter(Mandatory = $true)]
        [String]$Icon,

        [Parameter(Mandatory = $true)]
        [String]$Color,

        [Alias('icon_color')]
        [Parameter(Mandatory = $true)]
        [String]$IconColor,

        [Alias('include_passwords')]
        [bool]$IncludePasswords = $false,

        [Alias('include_photos')]
        [bool]$IncludePhotos = $false,

        [Alias('include_comments')]
        [bool]$IncludeComments = $false,

        [Alias('include_files')]
        [bool]$IncludeFiles = $false,

        [Alias('password_types')]
        [String]$PasswordTypes = '',

        [Parameter(Mandatory = $true)]
        [system.collections.generic.list[hashtable]]$Fields
    )

    foreach ($field in $fields) {
        if ($field.show_in_list) { $field.show_in_list = [System.Convert]::ToBoolean($field.show_in_list) } else { $field.remove('show_in_list') }
        if ($field.required) { $field.required = [System.Convert]::ToBoolean($field.required) } else { $field.remove('required') }
        if ($field.expiration) { $field.expiration = [System.Convert]::ToBoolean($field.expiration) } else { $field.remove('expiration') }
        # A bug in versions of Hudu 2.27 and earlier can cause asset layouts to become corrupted if the field type value is not properly cased.
        switch ($field.'field_type') {
            'text'              { $field.'field_type' = 'Text' }
            'richtext'          { $field.'field_type' = 'RichText' }
            'heading'           { $field.'field_type' = 'Heading' }
            'checkbox'          { $field.'field_type' = 'CheckBox' }
            'number'            { $field.'field_type' = 'Number' }
            'date'              { $field.'field_type' = 'Date' }
            'dropdown'          { Write-Warning "Dropdown Field Types have been deprecated but still available via the API. Please use ListSelect types moving forward if possible. This is not a failure."; $field.'field_type' = 'Dropdown' }
            'embed'             { $field.'field_type' = 'Embed' }
            'phone'             { $field.'field_type' = 'Phone' }
            'email'             { $field.'field_type' = 'Email' }
            'copyabletext'      { $field.'field_type' = 'Email' }
            'address'           { $field.'field_type' = 'AddressData' }
            'addressdata'       { $field.'field_type' = 'AddressData' }
            'assettag'          { $field.'field_type' = 'AssetTag' }
            'assetlink'         { $field.'field_type' = 'AssetTag' }
            'divider'           { $field.'field_type' = 'Divider' }
            'seperator'          { $field.'field_type' = 'Divider' }
            'website'           { $field.'field_type' = 'Website' }
            'link'              { $field.'field_type' = 'Website' }
            'password'          { $field.'field_type' = 'Password' }
            'confidentialtext'  { $field.'field_type' = 'Password' }
            'listselect' { $field.'field_type' = 'ListSelect' }
            Default { throw "Invalid field type: $($field.'field_type') found in field $($field.name)" }
        }
    }

    $AssetLayout = [ordered]@{asset_layout = [ordered]@{} }

    $AssetLayout.asset_layout.add('name', $Name)
    $AssetLayout.asset_layout.add('icon', $Icon)
    $AssetLayout.asset_layout.add('color', (ConvertTo-HuduLabelColor -Color $Color))
    $AssetLayout.asset_layout.add('icon_color', (ConvertTo-HuduLabelColor -Color $IconColor))
    $AssetLayout.asset_layout.add('fields', $Fields)
    #$AssetLayout.asset_layout.add('active', $Active)

    if ($IncludePasswords) {
        $AssetLayout.asset_layout.add('include_passwords', [System.Convert]::ToBoolean($IncludePasswords))
    }

    if ($IncludePhotos) {
        $AssetLayout.asset_layout.add('include_photos', [System.Convert]::ToBoolean($IncludePhotos))
    }

    if ($IncludeComments) {
        $AssetLayout.asset_layout.add('include_comments', [System.Convert]::ToBoolean($IncludeComments))
    }

    if ($IncludeFiles) {
        $AssetLayout.asset_layout.add('include_files', [System.Convert]::ToBoolean($IncludeFiles))
    }

    if ($PasswordTypes) {
        $AssetLayout.asset_layout.add('password_types', $PasswordTypes)
    }

    if ($PSBoundParameters.ContainsKey('SidebarFolderID')) {
        $AssetLayout.asset_layout.add('sidebar_folder_id', $SidebarFolderID)
    }

    if ($Slug) {
        $AssetLayout.asset_layout.add('slug', $Slug)
    }

    $JSON = $AssetLayout | ConvertTo-Json -Depth 10

    Write-Verbose $JSON

    if ($PSCmdlet.ShouldProcess($Name)) {
        Invoke-HuduRequest -Method post -Resource '/api/v1/asset_layouts' -Body $JSON
    }
}
#EndRegion '.\Public\New-HuduAssetLayout.ps1' 177
#Region '.\Public\New-HuduBaseURL.ps1' -1

function New-HuduBaseURL {
    <#
    .SYNOPSIS
    Set Hudu Base URL

    .DESCRIPTION
    In order to access the Hudu API the Base URL must be set

    .PARAMETER BaseURL
    Url with no trailing slash e.g. https://demo.huducloud.com

    .EXAMPLE
    New-HuduBaseURL -BaseURL https://demo.huducloud.com

    .NOTES
    General notes
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Scope = 'Function')]
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true)]
        [String]
        $BaseURL
    )
    process {
        if (!$BaseURL) {
            $BaseURL = Read-Host -Prompt 'Please enter your Hudu Base URL with no trailing /, for example https://demo.huducloud.com :'
        }
            
        $Protocol = $BaseURL[0..7] -join ''
            if ($Protocol -ne 'https://') {
                if ($Protocol -like 'http://*') {
                    Write-Warning "Non HTTPS Base URL was set, rewriting URL to be secure transport only. If connection fails please make sure hostname is correct and HTTPS is enabld."
                    $BaseURL = $BaseURL.Replace('http://','https://')
                }
                else {
                    Write-Warning "No protocol was specified, adding https:// to the beginning of the specified hostname"
                    $BaseURL = "https://$BaseURL"
                }
            }
        
        Set-Variable -Name 'Int_HuduBaseURL' -Value $BaseURL -Visibility Private -Scope script -Force

        if ($script:Int_HuduAPIKey) {
            [version]$script:Version = (Get-HuduAppInfo).version
            if ($script:Version -lt $script:HuduRequiredVersion) {
                Write-Warning "A connection error occured or Hudu version $($script:Version ?? "unknown") is below $script:HuduRequiredVersion"
            }
        }
    }
}
#EndRegion '.\Public\New-HuduBaseURL.ps1' 53
#Region '.\Public\New-HuduCompany.ps1' -1

function New-HuduCompany {
    <#
    .SYNOPSIS
    Create a company

    .DESCRIPTION
    Uses Hudu API to create a new company

    .PARAMETER Name
    Company name

    .PARAMETER Nickname
    Company nickname

    .PARAMETER CompanyType
    Company type

    .PARAMETER AddressLine1
    Address line 1

    .PARAMETER AddressLine2
    Address line 2

    .PARAMETER City
    City

    .PARAMETER State
    State

    .PARAMETER Zip
    Zip

    .PARAMETER CountryName
    Country

    .PARAMETER PhoneNumber
    Phone number

    .PARAMETER FaxNumber
    Fax number

    .PARAMETER Website
    Website

    .PARAMETER IdNumber
    Company id number

    .PARAMETER ParentCompanyId
    Parent company id number

    .PARAMETER Notes
    Parameter description

    .PARAMETER Slug
    Url identifier

    .EXAMPLE
    New-HuduCompany -Name 'Company name'

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [String]$Name,

        [String]$Nickname = '',

        [Alias('company_type')]
        [String]$CompanyType = '',

        [Alias('address_line_1')]
        [String]$AddressLine1 = '',

        [Alias('address_line_2')]
        [String]$AddressLine2 = '',

        [String]$City = '',

        [String]$State = '',

        [Alias('PostalCode', 'PostCode')]
        [String]$Zip = '',

        [Alias('country_name')]
        [String]$CountryName = '',

        [Alias('phone_number')]
        [String]$PhoneNumber = '',

        [Alias('fax_number')]
        [String]$FaxNumber = '',

        [String]$Website = '',

        [Alias('id_number')]
        [String]$IdNumber = '',

        [Alias('parent_company_id')]
        [int]$ParentCompanyId,

        [String]$Notes = '',

        [string]$Slug
    )


    $Company = [ordered]@{company = [ordered]@{} }

    $Company.company.add('name', $Name)
    if (-not ([string]::IsNullOrEmpty($Nickname))) { $Company.company.add('nickname', $Nickname) }
    if (-not ([string]::IsNullOrEmpty($CompanyType))) { $Company.company.add('company_type', $CompanyType) }
    if (-not ([string]::IsNullOrEmpty($AddressLine1))) { $Company.company.add('address_line_1', $AddressLine1) }
    if (-not ([string]::IsNullOrEmpty($AddressLine2))) { $Company.company.add('address_line_2', $AddressLine2) }
    if (-not ([string]::IsNullOrEmpty($City))) { $Company.company.add('city', $City) }
    if (-not ([string]::IsNullOrEmpty($State))) { $Company.company.add('state', $State) }
    if (-not ([string]::IsNullOrEmpty($Zip))) { $Company.company.add('zip', $Zip) }
    if (-not ([string]::IsNullOrEmpty($CountryName))) { $Company.company.add('country_name', $CountryName) }
    if (-not ([string]::IsNullOrEmpty($PhoneNumber))) { $Company.company.add('phone_number', $PhoneNumber) }
    if (-not ([string]::IsNullOrEmpty($FaxNumber))) { $Company.company.add('fax_number', $FaxNumber) }
    if (-not ([string]::IsNullOrEmpty($Website))) { $Company.company.add('website', $Website) }
    if (-not ([string]::IsNullOrEmpty($IdNumber))) { $Company.company.add('id_number', $IdNumber) }
    if (-not ([string]::IsNullOrEmpty($ParentCompanyId))) { $Company.company.add('parent_company_id', $ParentCompanyId) }
    if (-not ([string]::IsNullOrEmpty($Notes))) { $Company.company.add('notes', $Notes) }
    if (-not ([string]::IsNullOrEmpty($Slug))) { $Company.company.add('slug', $Slug) }

    $JSON = $Company | ConvertTo-Json -Depth 10
    Write-Verbose $JSON

    if ($PSCmdlet.ShouldProcess($Name)) {
        Invoke-HuduRequest -Method post -Resource '/api/v1/companies' -Body $JSON
    }
}
#EndRegion '.\Public\New-HuduCompany.ps1' 133
#Region '.\Public\New-HuduCustomHeaders.ps1' -1

function New-HuduCustomHeaders {
    <#
    .SYNOPSIS
    Set Hudu custom headers to be injected into each request

    .DESCRIPTION
    There may be times when one might need to use custom headers e.g. Service Tokens for Cloudflare Zero Trust

    .PARAMETER Headers
    Hashtable with the Custom Headers that need to be injected into each request

    .EXAMPLE
    New-HuduCustomHeaders -Headers @{"CF-Access-Client-Id" = "x"; "CF-Access-Client-Secret" = "y"}

    .NOTES
    General notes
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Scope = 'Function')]
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true)]
        [hashtable]
        $Headers
    )
    process {
        if ($Headers.Count -eq 0) {
            Write-Host "Empty Custom Header hashtable was provided, no Custom Headers will be set"
            return 0
        }
        
        Set-Variable -Name 'Int_HuduCustomHeaders' -Value $Headers -Visibility Private -Scope script -Force
    }
}
#EndRegion '.\Public\New-HuduCustomHeaders.ps1' 35
#Region '.\Public\New-HuduFlag.ps1' -1

function New-HuduFlag {
<#
.SYNOPSIS
Creates a Flag on a Hudu object (asset, website, article, etc.).

.DESCRIPTION
Creates a new Flag record in Hudu by associating a Flag Type with a specific object
(e.g., a Company, Asset, Network, VLAN). Use FlagTypeId to choose the flag style/color,
and Flagable_Type + Flagable_Id to point at the target object.

.PARAMETER FlagTypeId
The ID of the Flag Type to apply. Use Get-HuduFlagTypes to discover IDs.

.PARAMETER Description
Optional note shown on the flag. Useful for context like "Needs review" or "Decommission pending".

.PARAMETER Flagable_Type
The type of object to attach the flag to (e.g., Company, Asset, Website, Network).
This value is normalized to Hudu's canonical flagable_type before the request is sent.

.PARAMETER flagable_id
The ID of the target object (matching Flagable_Type). For example, a Company ID if Flagable_Type is Company.

.EXAMPLE
# Flag company 123 with flag type 5
New-HuduFlag -FlagTypeId 5 -Flagable_Type Company -flagable_id 123 -Description "Contract renewal due"

.EXAMPLE
# Flag asset 88 with flag type 2
New-HuduFlag -FlagTypeId 2 -Flagable_Type Asset -flagable_id 88

.NOTES
API Endpoint: POST /api/v1/flags
Requires Hudu API access configured for Invoke-HuduRequest.
#>    
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [int]$FlagTypeId,

        [Parameter()]
        [string]$Description,
    
        [Parameter(Mandatory)]
        [Alias('flaggabletype','flaggable_type','flagabletype','Flag_type','FlagType')]
        [ValidateScript({Assert-AllowedObjectType -InputType $_ -AllowedCanonicals @(
                "Vlan", "Procedure", "Website", "RackStorage", "Network", "IpAddress", "Article", "Company", "AssetPassword", "Asset","VlanZone"
        )})]
        [string]$Flagable_Type,

        [Parameter(Mandatory)]
        [Alias("FlaggableId","flaggable_id","flagableid")]
        [int]$flagable_id
    )

    $bodyObj = @{
        flag = @{
            flag_type_id  = $FlagTypeId
            description   = $Description
            flagable_type = $(Get-ObjectTypeFromCononical -inputData $Flagable_Type)
            flagable_id   = $flagable_id
        }
    }

    $body = $bodyObj | ConvertTo-Json -Depth 99

    if ($PSCmdlet.ShouldProcess("$flagable_type Id=$flagable_id", "Create Flag (FlagTypeId=$FlagTypeId)")) {
        $resp = Invoke-HuduRequest -Method POST -Resource "/api/v1/flags" -Body $body
        return ($resp.flag ?? $resp)
    }
}
#EndRegion '.\Public\New-HuduFlag.ps1' 72
#Region '.\Public\New-HuduFlagType.ps1' -1

function New-HuduFlagType {
<#
.SYNOPSIS
Creates a new Flag Type.

.DESCRIPTION
Creates a Flag Type (name + color) that can be applied to objects via New-HuduFlag.
Flag Types are reusable and are referenced by ID (flag_type_id) when creating Flags.

.PARAMETER Name
Display name for the Flag Type (e.g., "Needs Review", "Security Risk", "Onboarding").

.PARAMETER Color
Color name (canonicalized to Hudu). Controls the UI color used when displaying the flag.

.EXAMPLE
New-HuduFlagType -Name "Security Risk" -Color Red

.NOTES
API Endpoint: POST /api/v1/flag_types
#>

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('red', 'crimson', 'scarlet', 'rot', 'karminrot', 'scharlachrot', 'rouge', 'cramoisi', 'écarlate', 'rosso', 'cremisi', 'scarlatto', 'rojo', 'carmesí', 'escarlata', 'blue', 'navy', 'blau', 'marineblau', 'bleu', 'bleu marine', 'blu', 'blu navy', 'azul', 'azul marino', 'green', 'lime', 'grün', 'limettengrün', 'vert', 'vert citron', 'verde', 'verde lime', 'verde lima', 'yellow', 'gold', 'gelb', 'jaune', 'or', 'giallo', 'oro', 'amarillo', 'purple', 'violet', 'lila', 'violett', 'pourpre', 'viola', 'porpora', 'púrpura', 'violeta', 'orange', 'arancione', 'naranja', 'light pink', 'pink', 'baby pink', 'hellrosa', 'rosa', 'rose clair', 'rose', 'rosa chiaro', 'rosa claro', 'light blue', 'baby blue', 'sky blue', 'hellblau', 'babyblau', 'himmelblau', 'bleu clair', 'bleu ciel', 'azzurro', 'blu chiaro', 'azul claro', 'celeste', 'light green', 'mint', 'hellgrün', 'mintgrün', 'vert clair', 'menthe', 'verde chiaro', 'menta', 'verde claro', 'light purple', 'lavender', 'helllila', 'lavendel', 'violet clair', 'lavande', 'viola chiaro', 'lavanda', 'morado claro', 'light orange', 'peach', 'hellorange', 'pfirsich', 'orange clair', 'pêche', 'arancione chiaro', 'pesca', 'naranja claro', 'melocotón', 'light yellow', 'cream', 'hellgelb', 'creme', 'jaune clair', 'crème', 'giallo chiaro', 'crema', 'amarillo claro', 'white', 'weiß', 'blanc', 'bianco', 'blanco', 'grey', 'gray', 'silver', 'grau', 'silber', 'gris', 'argent', 'grigio', 'argento', 'plateado', 'lightpink', 'lightblue', 'lightgreen', 'lightpurple', 'lightorange', 'lightyellow',IgnoreCase = $true)]
        [string]$Color
    )
    $bodyObj = @{
        flag_type = @{
            name  = $Name
            color = $(Set-ColorFromCanonical -inputData $Color)
        }
    }

    $body = $bodyObj | ConvertTo-Json -Depth 99

    if ($PSCmdlet.ShouldProcess("Flag Type '$Name'", "Create")) {
        $resp = Invoke-HuduRequest -Method POST -Resource "/api/v1/flag_types" -Body $body
        return ($resp.flag_type ?? $resp)
    }
}
#EndRegion '.\Public\New-HuduFlagType.ps1' 48
#Region '.\Public\New-HuduFolder.ps1' -1

function New-HuduFolder {
    <#
    .SYNOPSIS
    Create a Folder

    .DESCRIPTION
    Uses Hudu API to create a new folder

    .PARAMETER Name
    Name of the folder

    .PARAMETER Icon
    Folder Icon

    .PARAMETER Description
    Folder description

    .PARAMETER ParentFolderId
    Parent folder ID

    .PARAMETER CompanyId
    Company id

    .PARAMETER folderType
    Folder type. Accepts "article" or "photo". Default is "article".

    .EXAMPLE
    New-HuduFolder -Name 'Test folder' -CompanyId 1

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [String]$Name,
        [String]$Icon,
        [String]$Description,
        [Alias('parent_folder_id')]
        [Nullable[int]]$ParentFolderId,
        [Alias('company_id')]
        [Nullable[int]]$CompanyId,
        [ValidateSet("article","photo", ignoreCase = $true)]
        [Alias('folder_type')]
        [string]$folderType='article'
    )

    $Folder = [ordered]@{folder = [ordered]@{} }

    $Folder.folder.add('name', $Name)

    if ($PSBoundParameters.ContainsKey('Icon')) {
        $Folder.folder.add('icon', $Icon)
    }

    if ($PSBoundParameters.ContainsKey('Description')) {
        $Folder.folder.add('description', $Description)
    }

    if ($PSBoundParameters.ContainsKey('ParentFolderId')) {
        $Folder.folder.add('parent_folder_id', $ParentFolderId)
    }

    if ($PSBoundParameters.ContainsKey('CompanyId')) {
        $Folder.folder.add('company_id', $CompanyId)
    }

    $Folder.folder.add('folder_type', "$FolderType".ToLower())

    $JSON = $Folder | ConvertTo-Json

    if ($PSCmdlet.ShouldProcess($Name)) {
        Invoke-HuduRequest -Method post -Resource '/api/v1/folders' -Body $JSON
    }
}
#EndRegion '.\Public\New-HuduFolder.ps1' 74
#Region '.\Public\New-HuduIPAddress.ps1' -1

function New-HuduIPAddress {
<#
.SYNOPSIS
Create a new Hudu IP address.

.DESCRIPTION
Creates a Hudu IPAM IP address record within a specific Company and Network.
Returns the created IP address object on success, or $null on failure.

.PARAMETER Address
The IP address to create (required). Example: '192.168.10.15'.

.PARAMETER NetworkId
Parent Network ID to associate with (required).

.PARAMETER CompanyId
Company ID to associate with (required).

.PARAMETER Status
IP status string as used by Hudu (e.g. 'active', 'reserved', 'available').

.PARAMETER FQDN
Optional FQDN for this IP.

.PARAMETER Description
Free-form description for the IP record.

.PARAMETER Notes
Free-form notes for the IP record.

.PARAMETER AssetId
Related Asset ID to link this IP to.

.PARAMETER SkipDNSValidation
If $true, the server should skip DNS validation for FQDN (default: $true). [note- DNS validation only works if your hudu instance can resolve dns to this address, so public or same-private network]

.OUTPUTS
pscustomobject (the created IP address object) or $null on failure.

.EXAMPLE
New-HuduIPAddress -Address '10.20.30.15' -CompanyId 42 -NetworkId 7 -Status reserved

.EXAMPLE
New-HuduIPAddress -Address '172.16.0.10' -CompanyId 42 -NetworkId 7 -FQDN 'printer01.example.com' -Description 'Front office printer'

.NOTES
Status is passed through as provided; the module lowercases certain fields as needed by the API.
SkipDNSValidation is sent as a lowercased string value ('true'/'false') per API expectations.
#>

    param(
        [Parameter(Mandatory)]
        [string]$Address,
        [Parameter(Mandatory)]
        [int]$NetworkId,
        [Parameter(Mandatory)]
        [int]$CompanyID,
        [string]$Status,
        [string]$FQDN,
        [string]$Description='',
        [string]$Notes='',
        [int]$AssetID,
        [bool]$SkipDNSValidation=$true
    )
    if (@($Address, $CompanyId, $NetworkId) -contains $null) {
        Write-Warning "Missing required item(s)"
        return $null
    }
    $newaddress= @{
        address         = $Address
        company_id      = $CompanyId
        network_id      = $NetworkId
    }

    if ($Status){
        $newaddress["status"]=$Status
    }    
    if ($FQDN){
        $newaddress["fqdn"]=$FQDN
    }
    if ($Description){
        $newaddress["description"]=$description
    }
    if ($Notes){
        $newaddress["notes"]=$Notes
    }    
    if ($AssetId){
        $newaddress["asset_id"]=$AssetId
    }   
    if ($SkipDNSValidation){
        $newaddress["skip_dns_validation"]="$($SkipDNSValidation)".ToLower()
    } else {
        $newaddress["skip_dns_validation"]="true"
    }

    $payload = $newaddress | ConvertTo-Json -depth 10
    try {
        $response = Invoke-HuduRequest -Method POST -Resource "/api/v1/ip_addresses" -Body $payload
        return $response
    } catch {
        Write-Warning "Failed to create address '$Name'"
        return $null
    }
}
#EndRegion '.\Public\New-HuduIPAddress.ps1' 105
#Region '.\Public\New-HuduLabel.ps1' -1

function New-HuduLabel {
<#
.SYNOPSIS
Creates a Label on a Hudu record.

.DESCRIPTION
Creates a new Label record in Hudu by associating a Label Type with a specific
record. The Label Type must be applicable to the target record type.

.PARAMETER LabelTypeId
The ID of the Label Type to apply. Use Get-HuduLabelTypes to discover IDs.

.PARAMETER Labelable_Type
The type of object to attach the label to.

.PARAMETER Labelable_Id
The ID of the target object matching Labelable_Type.

.EXAMPLE
New-HuduLabel -LabelTypeId 5 -Labelable_Type Asset -Labelable_Id 123

.NOTES
API Endpoint: POST /api/v1/labels
#>

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [Alias('label_type_id','labeltype_id','label_typeid','label_type','type_id','typeid')]
        [int]$LabelTypeId,

        [Parameter(Mandatory)]
        [ValidateScript({ Assert-AllowedObjectType -InputType $_ -AllowedCanonicals @(
            'Article', 'Asset', 'AssetPassword', 'Website', 'IpAddress', 'Vlan', 'VlanZone', 'Procedure', 'Network', 'RackStorage'
        ) })]
        [Alias('object_type','objectType','target_type','targetType')]
        [string]$Labelable_Type,

        [Parameter(Mandatory)]
        [Alias('object_id','objectID','target_id','targetId')]
        [int]$Labelable_Id
    )

    $canonicalLabelableType = Get-ObjectTypeFromCononical -inputData $Labelable_Type
    $bodyObj = @{
        label = @{
            label_type_id  = $LabelTypeId
            labelable_type = $canonicalLabelableType
            labelable_id   = $Labelable_Id
        }
    }

    $body = $bodyObj | ConvertTo-Json -Depth 99

    if ($PSCmdlet.ShouldProcess("$canonicalLabelableType Id=$Labelable_Id", "Create Label (LabelTypeId=$LabelTypeId)")) {
        $resp = Invoke-HuduRequest -Method POST -Resource "/api/v1/labels" -Body $body
        return ($resp.label ?? $resp)
    }
}
#EndRegion '.\Public\New-HuduLabel.ps1' 60
#Region '.\Public\New-HuduLabelType.ps1' -1

function New-HuduLabelType {
<#
.SYNOPSIS
Creates a new Label Type.

.DESCRIPTION
Creates a Label Type that can be applied to records via New-HuduLabel.
applicable_record_types must include one or more valid Hudu record types. When
AccessLevel is specific_companies, AllowedCompanyIds must contain at least one ID.

.PARAMETER Name
Display name for the Label Type.

.PARAMETER Color
Hex color value for the Label Type, such as #ff0000, or a human-readable color
name supported by Set-ColorFromCanonical. Alpha values are trimmed off.

.PARAMETER AccessLevel
Access scope for the Label Type. Defaults to all_companies.

.PARAMETER ApplicableRecordTypes
Record types this Label Type can be applied to. (can be english, spanish, italian)

.PARAMETER AllowedCompanyIds
Company IDs allowed to use this Label Type when AccessLevel is specific_companies.

.EXAMPLE
New-HuduLabelType -Name "Critical" -Color "#ffff00" -ApplicableRecordTypes Asset,Website

.EXAMPLE
New-HuduLabelType -Name "Private" -Color "green" -AccessLevel specific_companies -ApplicableRecordTypes Asset -AllowedCompanyIds 1,2

.EXAMPLE
New-HuduLabelType -Name "Orange" -Color "naranja" -ApplicableRecordTypes @("asset","motdepasse","internetseite","procédure","netzwerk")

.NOTES
API Endpoint: POST /api/v1/label_types
#>

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Color,

        [Parameter()]
        [ValidateSet('all_companies', 'all', 'allcompanies', 'allcompany', 'specific_companies', 'specific', 'specificcompanies', 'specificcompany', IgnoreCase = $true)]
        [Alias('access_level')]
        [string]$AccessLevel = 'all_companies',

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
            foreach ($recordType in $_) {
                Assert-AllowedObjectType -InputType $recordType -AllowedCanonicals @(
                    'Article', 'Asset', 'AssetPassword', 'Website', 'IpAddress', 'Vlan', 'VlanZone', 'Procedure', 'Network', 'RackStorage'
                ) | Out-Null
            }
            $true
        })]
        [Alias('applicable_record_types','record_types','types','applicableTypes','applicable_type','applicableType')]
        [string[]]$ApplicableRecordTypes,

        [Parameter()]
        [Alias('allowed_company_ids','companyids','company_ids','companyId','company_id','companies')]
        [int[]]$AllowedCompanyIds
    )
    $AccessLevelMap = @{
        'all_companies'             = 'all_companies'
        'all'                       = 'all_companies'
        'allcompanies'              = 'all_companies'
        'allcompany'                = 'all_companies'
        'specific_companies'        = 'specific_companies'
        'specific'                  = 'specific_companies'
        'specificcompanies'         = 'specific_companies'
        'specificcompany'           = 'specific_companies'
    }
    $accesslevelNormalized = $AccessLevelMap[$AccessLevel.ToLower()]


    if ($accesslevelNormalized -eq 'specific_companies' -and -not $AllowedCompanyIds) {
        throw "AllowedCompanyIds must contain at least one company ID when AccessLevel is specific_companies."
    }

    $labelType = @{
        name                    = $Name
        color                   = ConvertTo-HuduLabelColor -Color $Color
        access_level            = $accesslevelNormalized
        applicable_record_types = @($ApplicableRecordTypes | ForEach-Object { Get-ObjectTypeFromCononical -inputData $_ })
    }

    if ($accesslevelNormalized -eq 'specific_companies') {
        $labelType.allowed_company_ids = @($AllowedCompanyIds)
    }

    $body = @{ label_type = $labelType } | ConvertTo-Json -Depth 99

    if ($PSCmdlet.ShouldProcess("Label Type '$Name'", "Create")) {
        $resp = Invoke-HuduRequest -Method POST -Resource "/api/v1/label_types" -Body $body
        return ($resp.label_type ?? $resp)
    }
}
#EndRegion '.\Public\New-HuduLabelType.ps1' 107
#Region '.\Public\New-HuduList.ps1' -1

function New-HuduList {
    <#
    .SYNOPSIS
    Create a new Hudu List

    .DESCRIPTION
    Calls the Hudu API to create a new List with the specified name and items.

    .PARAMETER Name
    Name of the new list

    .PARAMETER Items
    An array of item names to include in the list

    .EXAMPLE
    New-HuduList -Name "Device Status" -Items @("Online", "Offline", "Decommissioned")
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string[]]$Items
    )

    $listItems = $Items | ForEach-Object { @{ name = $_ } }

    $payload = @{
        list = @{
            name = $Name
            list_items_attributes = $listItems
        }
    } | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-HuduRequest -Method POST -Resource "/api/v1/lists" -Body $payload
        return $response
    } catch {
        Write-Warning "Failed to create list '$Name'"
        return $null
    }
}
#EndRegion '.\Public\New-HuduList.ps1' 44
#Region '.\Public\New-HuduNetwork.ps1' -1

function New-HuduNetwork {
<#
.SYNOPSIS
Create a new Hudu network.

.DESCRIPTION
Creates a new hudu IPAM Network Object for a Company.
Name, Address (or CIDR Address Range) and CompanyId are required.
Returns the created network object on success, or $null on failure.

.PARAMETER Name
Display name for the network. (Required)

.PARAMETER Address
CIDR notation for the network (e.g. 10.0.0.0/24). (Required)

.PARAMETER CompanyId
Company ID to associate with the network. (Required)

.PARAMETER LocationId
Optional location ID to associate with the network.

.PARAMETER Description
Free-form description of the network.

.PARAMETER NetworkType
Numeric network type as used by Hudu (module/API enum value).

.PARAMETER VlanId
VLAN identifier for the network.

.EXAMPLE
New-HuduNetwork -Name "Core LAN" -Address "192.168.10.0/24" -CompanyId 42

.EXAMPLE
New-HuduNetwork -Name "Server VLAN 30" -Address "10.20.30.0/24" -CompanyId 42 -LocationId 7 -VlanId 30 -NetworkType 1
#>    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [string]$Address,
        [Parameter(Mandatory)]
        [int]$CompanyId,
        [int]$LocationId,
        [string]$Description,
        [int]$NetworkType,
        [int]$VlanId
    )
    if (@($Name, $Address, $CompanyId) -contains $null) {
        Write-Warning "Missing required item."
        return $null
    }


    $network= @{
        name            = $Name
        address         = $Address
        company_id      = $CompanyId
    }
    if ($Description){
        $network["description"]=$description
    }
    if ($networkType){
        $network["network_type"]=$networkType
    }
    if ($LocationId){
        $network["location_id"]=$LocationId
    }
    if ($vlanId){
        $network["vlan_id"]=$vlanId
    }


    $payload = $network | ConvertTo-Json -depth 10
    try {
        $response = Invoke-HuduRequest -Method POST -Resource "/api/v1/networks" -Body $payload
        return $response
    } catch {
        Write-Warning "Failed to create network '$Name'"
        return $null
    }
}
#EndRegion '.\Public\New-HuduNetwork.ps1' 85
#Region '.\Public\New-HuduPassword.ps1' -1

function New-HuduPassword {
    <#
    .SYNOPSIS
    Create a Password

    .DESCRIPTION
    Uses Hudu API to create a new password

    .PARAMETER Name
    Name of the password

    .PARAMETER CompanyId
    Company id

    .PARAMETER PasswordableType
    associated Object type, most commonly asset, for the password ["Asset"]

    .PARAMETER PasswordableId
    Associated object id for the password

    .PARAMETER InPortal
    Boolean for in portal

    .PARAMETER Password
    Password

    .PARAMETER OTPSecret
    OTP secret

    .PARAMETER URL
    Password URL

    .PARAMETER Username
    Username

    .PARAMETER Description
    Password description

    .PARAMETER PasswordType
    Password type

    .PARAMETER PasswordFolderId
    Password folder id

    .PARAMETER Slug
    Url identifier

    .EXAMPLE
    New-HuduPassword -Name 'Some website password' -Username 'user@domain.com' -Password '12345'

    #>
    [CmdletBinding(SupportsShouldProcess)]
    # This will silence the warning for variables with Password in their name.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingUsernameAndPasswordParams', '')]
    Param (
        [Parameter(Mandatory = $true)]
        [String]$Name,

        [Alias('company_id')]
        [Parameter(Mandatory = $true)]
        [Int]$CompanyId,

        [Alias('passwordable_type')]
        [ValidateScript({Assert-AllowedObjectType -InputType $_ -AllowedCanonicals @(
                "Asset"
        )})]        
        [String]$PasswordableType,

        [Alias('passwordable_id')]
        [int]$PasswordableId,

        [Alias('in_portal')]
        [Bool]$InPortal = $false,

        [Parameter(Mandatory = $true)]
        [String]$Password,

        [Alias('otp_secret')]
        [string]$OTPSecret,

        [String]$URL,

        [String]$Username,

        [String]$Description,

        [Alias('password_type')]
        [String]$PasswordType,

        [Alias('password_folder_id')]
        [int]$PasswordFolderId,

        [string]$Slug
    )

    $AssetPassword = [ordered]@{asset_password = [ordered]@{} }

    $AssetPassword.asset_password.add('name', $Name)
    $AssetPassword.asset_password.add('company_id', $CompanyId)
    $AssetPassword.asset_password.add('password', $Password)
    $AssetPassword.asset_password.add('in_portal', $InPortal)

    if ($PSBoundParameters.ContainsKey('PasswordableType'))   { 
            $AssetPassword.asset_password.add('passwordable_type', $(Get-ObjectTypeFromCononical -inputData $PasswordableType))
    }

    if ($PSBoundParameters.ContainsKey('OTPSecret'))   { 
        $AssetPassword.asset_password.add('otp_secret', $OTPSecret)
    }

    if ($PSBoundParameters.ContainsKey('URL'))   { 
        $AssetPassword.asset_password.add('url', $URL)
    }

    if ($PSBoundParameters.ContainsKey('Username'))   { 
        $AssetPassword.asset_password.add('username', $Username)
    }

    if ($PSBoundParameters.ContainsKey('Description'))   { 
        $AssetPassword.asset_password.add('description', $Description)
    }

    if ($PSBoundParameters.ContainsKey('PasswordType'))   { 
        $AssetPassword.asset_password.add('password_type', $PasswordType)
    }

    if ($PSBoundParameters.ContainsKey('PasswordFolderId') -and $PasswordFolderId -gt 0)   { 
        $AssetPassword.asset_password.add('password_folder_id', $PasswordFolderId)
    }
    if ($PSBoundParameters.ContainsKey('PasswordableId') -and $PasswordableId -gt 0) {
        $AssetPassword.asset_password.add('passwordable_id', $PasswordableId)
    }    

    if ($Slug) {
        $AssetPassword.asset_password.add('slug', $Slug)
    }

    $JSON = $AssetPassword | ConvertTo-Json -Depth 10

    if ($PSCmdlet.ShouldProcess($Name)) {
        Invoke-HuduRequest -Method post -Resource '/api/v1/asset_passwords' -Body $JSON
    }
}
#EndRegion '.\Public\New-HuduPassword.ps1' 145
#Region '.\Public\New-HuduPasswordFolder.ps1' -1

function New-HuduPasswordFolder {
    <#
    .SYNOPSIS
    Create a new password folder.

    .DESCRIPTION
    Calls the Hudu API to create a password folder for a given company.  
    Supports configuring name, description, security settings, and allowed groups.

    .PARAMETER Name
    Name of the new folder (required).

    .PARAMETER CompanyId
    The company ID that owns the folder (only required if not creating a global folder).

    .PARAMETER Description
    Description of the folder.

    .PARAMETER Security
    Security mode. Accepts "all_users" or "specific".

    .PARAMETER AllowedGroups
    Array of group IDs that should have access (if Security is "specific").

    .EXAMPLE
    New-HuduPasswordFolder -Name "Infrastructure" -CompanyId 2
    Creates a folder named "Infrastructure" for company ID 2.

    .EXAMPLE
    New-HuduPasswordFolder -Name "Finance" -CompanyId 4 -Security specific -AllowedGroups @(10,12)
    Creates a folder for company 4 restricted to groups 10 and 12.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name,
        
        [int]$CompanyId,
        
        [string]$Description,
        
        [ValidateSet("all_users","specific")]
        [String]$Security,
        
        [array]$AllowedGroups)

    $password_folder=@{
        name = $Name
    }
    if ($PSBoundParameters.ContainsKey('CompanyId')) {
        $password_folder.company_id = $CompanyId
    } else {
        # Assumed to be global password folder if not provided
        $password_folder.company_id = $null
    }
    if ($Description){
        $password_folder["description"] = $Description
    }
    if ($security -and $security -eq "specific"){
        $password_folder["security"] = $security
        $allGroups = $(Get-HuduGroups).id
        
        if ($($AllowedGroups | where-object {$allGroups -contains $_}).count -gt 0) {
            $password_folder["allowed_groups"]= $AllowedGroups | where-object {$allGroups -contains $_}
        } else {
            $password_folder["allowed_groups"]=@("0")
        }
    } else {
        $password_folder["security"] = 'all_users'
        $password_folder["allowed_groups"]= @()
    }
    $payload = @{password_folder = $password_folder} | ConvertTo-Json -Depth 10
    try {
        $res = Invoke-HuduRequest -Method POST -Resource "/api/v1/password_folders" -Body $payload
        return $res
    } catch {
        Write-Warning "Failed to create new password folder '$Name'"
        return $null
    }
}
#EndRegion '.\Public\New-HuduPasswordFolder.ps1' 81
#Region '.\Public\New-HuduPhoto.ps1' -1

function New-HuduPhoto {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Alias('File','FullName')]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Caption,

        [Alias('company_id')]
        [int]$CompanyId,
        
        [Alias('folder_id')]
        [int]$FolderId,

        [Alias('uploadabletype','recordtype','photoabletype','uploadable_type','record_type')]
        [ValidateScript({Assert-AllowedObjectType -InputType $_ -AllowedCanonicals @(
                "Website", "RackStorage", "IpAddress", "Article", "Company", "Asset", "AssetPassword"
        )})]
        [string]$Photoable_Type,

        [Alias('record_id','uploadable_id','recordid','PhotoableId','uploadableid')]
        [int]$Photoable_Id,

        [Nullable[bool]]$Pinned
    )

    [version]$script:Version = $script:Version ?? [version]((Get-HuduAppInfo).version)
    if ($script:Version -lt [version]'2.41.0') {
        write-warning "Set-HuduPhoto: Hudu version $($script:Version) is below 2.41.0; Skipping."
        return $null
    }

    $File = Get-Item -LiteralPath $Path
    if (-not $File) { throw "File not found!" }
    if (-not $($File.Extension.ToLowerInvariant() -in '.jpeg','.jpg','.png','.gif','.webp','.heic')){
        write-error "file extension '$($File.Extension)' is not a supported photo format."
        throw "Unsupported file format."
    }

    if (($Photoable_Type -and -not ($Photoable_Id ?? $companyId)) -or ($($Photoable_Id ?? $companyId) -and -not $Photoable_Type)) {
        throw "PhotoableType and PhotoableId must be provided together."
    }
    if ([string]::IsNullOrWhiteSpace($Caption)) {
        throw "Caption is required."
    }
    $params = @{file = $File; caption = $Caption;}
    if ($PSBoundParameters.ContainsKey('Photoable_Type') -and $PSBoundParameters.ContainsKey('Photoable_Id')) {         
        $params.photoable_type  = $(Get-ObjectTypeFromCononical -inputData $Photoable_Type)
        $params.photoable_id    = $Photoable_Id
    } elseif ($PSBoundParameters.ContainsKey('CompanyId')) { 
        $params.photoable_type = "Company"
        $params.photoable_id = $CompanyId
    }

    if ($PSBoundParameters.ContainsKey('CompanyId')) { $params.company_id = $CompanyId }
    if ($PSBoundParameters.ContainsKey('FolderId'))  { $params.folder_id = $FolderId }    

    if ($PSBoundParameters.ContainsKey('Pinned'))      { $params.pinned = [bool]$Pinned }
    if ($PSBoundParameters.ContainsKey('archived'))  { $params.archived = [bool]$Archived }

    Invoke-HuduRequest -Method POST -Resource '/api/v1/photos' -Form $params
}
#EndRegion '.\Public\New-HuduPhoto.ps1' 67
#Region '.\Public\New-HuduProcedure.ps1' -1

function New-HuduProcedure {
    <#
    .SYNOPSIS
    Create a new Hudu process template.

    .DESCRIPTION
    Creates a new process template by calling POST /api/v1/procedures.

    This endpoint creates process templates only. It does not create runs
    (active instances). To create a run from a process, use Start-HuduProcedure.

    Behavior:
    - If CompanyId is omitted, a global template is created.
    - If CompanyId is provided, a company-specific process is created.

    .PARAMETER Name
    Name of the process.

    .PARAMETER Description
    Description text for the process.

    .PARAMETER CompanyId
    Company ID for a company-specific process.
    If omitted, a global template is created.

    .PARAMETER CompanyTemplate
    Legacy/compatibility parameter. Included only when explicitly specified.

    .EXAMPLE
    New-HuduProcedure -Name "Onboarding" -Description "New employee onboarding" -CompanyId 123

    .EXAMPLE
    New-HuduProcedure -Name "Global Onboarding Template" -Description "Template for all companies"
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Description,

        [int]$CompanyId,

        [bool]$CompanyTemplate
    )

    $procedure = @{
        name = $Name
    }

    if ($PSBoundParameters.ContainsKey('Description')) {
        $procedure['description'] = $Description
    }

    if ($PSBoundParameters.ContainsKey('CompanyId')) {
        $procedure['company_id'] = $CompanyId
    }
    else {
        $procedure['company_id'] = $null
    }

    if ($PSBoundParameters.ContainsKey('CompanyTemplate')) {
        $procedure['company_template'] = $CompanyTemplate
    }

    $payload = $procedure | ConvertTo-Json -Depth 10

    try {
        $res = Invoke-HuduRequest -Method POST -Resource "/api/v1/procedures" -Body $payload
        return ($res.procedure ?? $res)
    }
    catch {
        Write-Warning "Failed to create procedure '$Name': $($_.Exception.Message)"
        return $null
    }
}
#EndRegion '.\Public\New-HuduProcedure.ps1' 77
#Region '.\Public\New-HuduProcedureFromTemplate.ps1' -1

function New-HuduProcedureFromTemplate {
    <#
    .SYNOPSIS
    Create a new process from a global template.

    .DESCRIPTION
    Calls POST /api/v1/procedures/{id}/create_from_template.

    The source procedure must be a global template.

    Behavior:
    - If CompanyId is supplied, creates a company-specific process.
    - If CompanyId is omitted, creates another global template copy.

    This cmdlet creates a process/template copy only. It does not create a run.

    .PARAMETER ProcedureId
    ID of the global template to copy from.

    .PARAMETER CompanyId
    Optional company ID for the new process.
    If omitted, a new global template copy is created.

    .PARAMETER Name
    Optional new name for the copied process.

    .PARAMETER Description
    Optional new description for the copied process.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Alias('Id')]
        [int]$ProcedureId,

        [int]$CompanyId,

        [string]$Name,

        [string]$Description
    )

    $procedureContext = Get-HuduProcedureContext -ProcedureId $ProcedureId
    if (-not $procedureContext) {
        throw "Could not determine procedure context for procedure ID $ProcedureId."
    }

    if ($procedureContext.IsRun) {
        Write-Warning "Procedure ID $ProcedureId is a run. Only global templates can be copied with create_from_template."
        return $null
    }

    if (-not $procedureContext.IsGlobal) {
        Write-Warning "Procedure ID $ProcedureId is not a global template. Only global templates can be copied with create_from_template."
        return $null

    $params = @{}
    if ($PSBoundParameters.ContainsKey('CompanyId'))   { $params.company_id = $CompanyId }
    if ($PSBoundParameters.ContainsKey('Name'))        { $params.name = $Name }
    if ($PSBoundParameters.ContainsKey('Description')) { $params.description = $Description }

    try {
        $res = Invoke-HuduRequest -Method POST -Resource "/api/v1/procedures/$ProcedureId/create_from_template" -Params $params
        return ($res.procedure ?? $res)
    }
    catch {
        Write-Warning "Failed to create procedure from template ID $ProcedureId- $($_.Exception.Message)"
        return $null
    }
}
}
#EndRegion '.\Public\New-HuduProcedureFromTemplate.ps1' 72
#Region '.\Public\New-HuduProcedureTask.ps1' -1

function New-HuduProcedureTask {
<#
.SYNOPSIS
Create a new procedure task.

.DESCRIPTION
Creates a new task associated with a procedure or procedure run.

Behavior differs depending on Hudu version:

- Pre-2.41.0:
  Tasks are created using legacy behavior. All provided fields are accepted
  and applied directly to the procedure task.

- 2.41.0 and later:
  Procedures are split into templates (processes) and runs (executions).
  Tasks may belong to either context.

Run-only fields:
  The following parameters only apply to tasks associated with runs:
    - Priority
    - UserId
    - AssignedUsers
    - DueDate

Forgiving behavior:
  - If run-only fields are provided for a non-run procedure, they are ignored
    and a warning is emitted.
  - If -AutoKickoff is specified and the procedure can be run, a run will be
    created automatically and the task will be associated with that run.
  - If -RunTask is specified but the target is not a run, the command will
    continue and create a template task, ignoring run-only fields.

This cmdlet is designed to be forgiving and will attempt to create the task
whenever possible, even if some parameters are not applicable in the current context.

.PARAMETER Name
Name of the task.

.PARAMETER ProcedureId
ID of the procedure or run to attach the task to.

.PARAMETER Description
Optional task description.

.PARAMETER Priority
Run-only. Priority level for the task.

.PARAMETER UserId
Run-only. Single user assignment.

.PARAMETER AssignedUsers
Run-only. Array of user IDs to assign.

.PARAMETER DueDate
Run-only. Due date for the task.

.PARAMETER Position
Optional ordering position.

.PARAMETER RunTask
Indicates intent to create a task on a run.
If the target is not a run, the command will attempt to proceed and may ignore
run-only fields.

.PARAMETER AutoKickoff
If specified and the target is a runnable procedure template, a run will be
created automatically and the task will be associated with that run.

#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [int]$ProcedureId,
        [string]$Description,
        [ValidateSet("unsure", "low", "normal", "high", "urgent")]
        [string]$Priority,
        [int]$UserId,
        [int[]]$AssignedUsers,
        [string]$DueDate,
        [int]$Position,
        # 2.41.0+ only
        [switch]$RunTask,
        [switch]$AutoKickoff
        )

    if (-not $script:HuduVersion) {
        [version]$script:HuduVersion = (Get-HuduAppInfo).version
    }

    if ($script:HuduVersion -lt [version]'2.41.0') {
        return New-HuduProcedureTaskLegacy @PSBoundParameters
    }

    return New-HuduProcedureTaskV241 @PSBoundParameters
}
#EndRegion '.\Public\New-HuduProcedureTask.ps1' 97
#Region '.\Public\New-HuduProcedureTaskLegacy.ps1' -1

function New-HuduProcedureTask {
    <#
    .SYNOPSIS
    Create a new procedure task

    .DESCRIPTION
    Creates a new task associated with a procedure.

    .PARAMETER Name
    Name of the task

    .PARAMETER ProcedureId
    ID of the procedure to attach the task to

    .PARAMETER Description
    Optional task description

    .PARAMETER Priority
    Optional priority level (e.g., "unsure", "low", "normal", "high", "urgent")

    .PARAMETER UserId
    Optional single user assignment

    .PARAMETER AssignedUsers
    Optional array of user IDs to assign

    .PARAMETER DueDate
    Optional due date (YYYY-MM-DD)

    .PARAMETER Position
    Optional ordering position

    .EXAMPLE
    New-HuduProcedureTask -Name "Initial Review" -ProcedureId 123 -Priority "high"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [int]$ProcedureId,
        [string]$Description,
        [ValidateSet("unsure", "low", "normal", "high", "urgent")]
        [string]$Priority,
        [int]$UserId,
        [int[]]$AssignedUsers,
        [string]$DueDate,
        [int]$Position,
        [switch]$RunTask, # ignored in legacy method
        [switch]$AutoKickoff # ignored in legacy method
    )

    $task = @{
        name         = $Name
        procedure_id = $ProcedureId
    }

    if ($Description)    { $task.description     = $Description }
    if ($Priority)       { $task.priority        = $Priority }
    if ($UserId)         { $task.user_id         = $UserId }
    if ($AssignedUsers)  { $task.assigned_users  = $AssignedUsers }
    if ($DueDate)        { $task.due_date        = $DueDate }
    if ($Position)       { $task.position        = $Position }

    $payload = @{ procedure_task = $task } | ConvertTo-Json -Depth 10

    try {
        $res = Invoke-HuduRequest -Method POST -Resource "/api/v1/procedure_tasks" -Body $payload
        return $res.procedure_task
    } catch {
        Write-Warning "Failed to create procedure task '$Name'"
        return $null
    }
}
#EndRegion '.\Public\New-HuduProcedureTaskLegacy.ps1' 73
#Region '.\Public\New-HuduProcedureTaskV241.ps1' -1

function New-HuduProcedureTaskV241 {
<#
.SYNOPSIS
Create a procedure task (Hudu 2.41.0+ behavior).

.DESCRIPTION
Creates a task for either a procedure template or a run.

Run-only fields (Priority, UserId, AssignedUsers, DueDate) are only applied
when the target is a run.

If run-only fields are provided for a template:
  - They are ignored
  - A warning is emitted

If -AutoKickoff is specified and the procedure is runnable:
  - A run is created automatically
  - The task is created on the run instead

This implementation is intentionally forgiving and will proceed whenever possible.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [int]$ProcedureId,

        [string]$Description,

        [int]$Position,

        [ValidateSet("unsure", "low", "normal", "high", "urgent")]
        [string]$Priority,

        [int]$UserId,

        [int[]]$AssignedUsers,

        [datetime]$DueDate,

        [switch]$RunTask,

        [switch]$AutoKickoff
    )

    $procedureContext = Get-HuduProcedureContext -ProcedureId $ProcedureId
    if (-not $procedureContext) {
        throw "Could not determine procedure context for procedure ID $ProcedureId."
    }

    $runOnlyFields = @('Priority','UserId','AssignedUsers','DueDate')
    $presentRunFields = @($runOnlyFields.Where({ $PSBoundParameters.ContainsKey($_) }))
    $runParamsPresent = $presentRunFields.Count -gt 0

    $isRun = ($procedureContext.IsRun -eq $true)

    if (-not $isRun -and $AutoKickoff -and $procedureContext.CanKickoff) {
        Write-Verbose "Procedure ID $ProcedureId is not a run. Attempting to kick off a run first."
        $run = Start-HuduProcedure -ProcedureId $ProcedureId; $run = $run.procedure ?? $run;

        if ($run -and $run.id) {
            $ProcedureId = [int]$run.id
            $isRun = $true
            Write-Verbose "Created run ID $ProcedureId for task creation."
        }
        else {
            Write-Warning "Failed to kick off a run for procedure ID $ProcedureId. Continuing without run-only fields."
        }
    }
    elseif (-not $isRun -and $RunTask) {
        Write-Warning "Procedure ID $ProcedureId is not a run. Creating a template/process task instead and ignoring run-only fields."
    }

    $task = @{
        name         = $Name
        procedure_id = $ProcedureId
    }

    if ($PSBoundParameters.ContainsKey('Description')) { $task.description = $Description }
    if ($PSBoundParameters.ContainsKey('Position'))    { $task.position    = $Position }

    if ($isRun) {
        if ($PSBoundParameters.ContainsKey('Priority'))      { $task.priority       = $Priority }
        if ($PSBoundParameters.ContainsKey('UserId'))        { $task.user_id        = $UserId }
        if ($PSBoundParameters.ContainsKey('AssignedUsers')) { $task.assigned_users = $AssignedUsers }
        if ($PSBoundParameters.ContainsKey('DueDate'))       { $task.due_date       = $DueDate.ToString('yyyy-MM-dd') }
    } elseif ($runParamsPresent) {
        [void]$task.Remove('priority')
        [void]$task.Remove('user_id')
        [void]$task.Remove('assigned_users')
        [void]$task.Remove('due_date')
        Write-Warning ("The following fields can only be set on run tasks and were ignored for procedure/template task creation: {0}" -f ($presentRunFields -join ', '))
    }

    $payload = @{ procedure_task = $task } | ConvertTo-Json -Depth 10

    try {
        $res = Invoke-HuduRequest -Method POST -Resource "/api/v1/procedure_tasks" -Body $payload
        return ($res.procedure_task ?? $res)
    }
    catch {
        Write-Warning "Failed to create procedure task '$Name': $($_.Exception.Message)"
        return $null
    }
}
#EndRegion '.\Public\New-HuduProcedureTaskV241.ps1' 108
#Region '.\Public\New-HuduPublicPhoto.ps1' -1

function New-HuduPublicPhoto {
    <#
    .SYNOPSIS
    Create a Public Photo

    .DESCRIPTION
    Uses Hudu API to upload an image for use in an asset or article

    .PARAMETER FilePath
    Path to the image

    .PARAMETER RecordId
    Record id to associate with the photo

    .PARAMETER RecordType
    Record type to associate with the photo

    .EXAMPLE
    New-HuduPublicPhoto -FilePath 'c:\path\to\image.png' -RecordId 1 -RecordType 'asset'

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Alias('record_id')]
        [int]$RecordId,

        [Alias('record_type')]
        [ValidateScript({Assert-AllowedObjectType -InputType $_ -AllowedCanonicals @(
                "Asset", "Article"
        )})]        
        [string]$RecordType
    )

    $File = Get-Item -LiteralPath $FilePath
    if (-not $File) {throw "File not found!"}
    $form = @{
        photo = $File
    }

    if ($RecordId) { $form['record_id'] = $RecordId }
    if ($RecordType) { $form['record_type'] = $RecordType }

    if ($PSCmdlet.ShouldProcess($File.FullName)) {
        Invoke-HuduRequest -Method POST -Resource '/api/v1/public_photos' -Form $form
    }
}
#EndRegion '.\Public\New-HuduPublicPhoto.ps1' 50
#Region '.\Public\New-HuduRackStorage.ps1' -1

function New-HuduRackStorage {
    <#
    .SYNOPSIS
    Creates a new Rack Storage in Hudu.

    .DESCRIPTION
    Sends a request to the Hudu API to create a new Rack Storage, including properties such as name, dimensions, location, and associated company.

    .PARAMETER Name
    The name of the new rack (e.g., "Rack A-01"). This is required.

    .PARAMETER LocationId
    The ID of the location where this rack is physically installed. Optional.

    .PARAMETER CompanyId
    The ID of the company associated with the rack. Optional, but useful for filtering.

    .PARAMETER Description
    A brief description or note for the rack (e.g., "Primary server rack"). Optional.

    .PARAMETER MaxWattage
    The maximum wattage supported by the rack. Optional.

    .PARAMETER StartingUnit
    The starting rack unit number (e.g., 1 if it's a full rack). Optional.

    .PARAMETER Height
    Total number of rack units (U) in height (e.g., 42 for a standard rack). Optional.

    .PARAMETER Width
    The width of the rack in millimeters or another defined unit (depending on Hudu's expected units). Optional.

    .EXAMPLE
    New-HuduRackStorage -Name "Rack A-01" -LocationId 12 -CompanyId 34 -Height 42 -StartingUnit 1

    Creates a new rack called "Rack A-01" at location ID 12, linked to company ID 34, with 42U height starting from unit 1.

    .EXAMPLE
    Get-HuduRackStorage -Id 101

    Returns the Rack Storage with ID 101.

    .NOTES
    API Endpoint: GET /api/v1/rack_storages/{id}
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [int]$CompanyId,

        [Parameter(Mandatory)]
        [int]$Height,

        [Parameter(Mandatory)]
        [int]$Width,

        [int]$LocationId,

        [string]$Description,

        [int]$MaxWattage,

        [int]$StartingUnit
    )

    $Body = @{
        name          = $Name
        location_id   = $LocationId
        company_id    = $CompanyId
        description   = $Description
        max_wattage   = $MaxWattage
        starting_unit = $StartingUnit
        height        = $Height
        width         = $Width
    } | ConvertTo-Json -Depth 10

    $HuduRequest = @{
        Method   = 'POST'
        Resource = '/api/v1/rack_storages'
        Body     = $Body
    }

    Invoke-HuduRequest @HuduRequest
}
#EndRegion '.\Public\New-HuduRackStorage.ps1' 88
#Region '.\Public\New-HuduRackStorageItem.ps1' -1

function New-HuduRackStorageItem {
    <#
    .SYNOPSIS
    Creates a new Rack Storage Item in Hudu.

    .DESCRIPTION
    Calls Hudu API to create a new rack storage item

    .PARAMETER RackStorageRoleId
    The ID of the rack storage role.

    .PARAMETER AssetId
    The ID of the asset to associate.

    .PARAMETER StartUnit
    The starting rack unit.

    .PARAMETER EndUnit
    The ending rack unit.

    .PARAMETER Status
    Integer status code for the rack storage item.

    .PARAMETER Side
    Rack side: 1 or 0.

    .PARAMETER MaxWattage
    Max wattage allowed in the rack section.

    .PARAMETER PowerDraw
    Power draw for the asset in watts.

    .PARAMETER ReservedMessage
    Optional reserved message for placeholder items.

    .PARAMETER CompanyId
    Company ID to associate with the rack item.

    .EXAMPLE
    New-HuduRackStorageItem -AssetId 123 -RackStorageRoleId 45 -StartUnit 1 -EndUnit 4 -Status 1 -Side "Front"

    Creates a new rack storage item (for asset id 123) designated for rack storage item role id of 45, from unit 1-4 on front of rack storage
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [int]$RackStorageId,

        [Parameter(Mandatory)]
        [int]$RackStorageRoleId,

        [Parameter(Mandatory)]
        [int]$AssetId,

        [Parameter(Mandatory)]
        [int]$StartUnit,

        [Parameter(Mandatory)]
        [int]$EndUnit,

        [Parameter(Mandatory)]
        [ValidateSet(0, 1)]
        [int]$Status,

        [Parameter(Mandatory)]
        [ValidateSet(0, 1)]
        [int]$Side,
        
        [int]$MaxWattage,
        
        [int]$PowerDraw,
        
        [string]$ReservedMessage,

        [Parameter(Mandatory)]
        [int]$CompanyId
    )
    $ItemPayload = @{
        rack_storage_id     = $RackStorageId
        asset_id            = $AssetId
        rack_storage_role_id = $RackStorageRoleId
        start_unit       = $StartUnit
        end_unit            = $EndUnit
        company_id          = $CompanyID
        side                = $Side
    }

    if ($MaxWattage)      { $ItemPayload.max_wattage = $MaxWattage }
    if ($PowerDraw)       { $ItemPayload.power_draw = $PowerDraw }
    if ($ReservedMessage) { $ItemPayload.reserved_message = $ReservedMessage }

    $Body = @{ rack_storage_item = $ItemPayload }

    $HuduRequest = @{
        Method   = 'POST'
        Resource = '/api/v1/rack_storage_items'
        Body     = ($Body | ConvertTo-Json -Depth 10)
    }

    Invoke-HuduRequest @HuduRequest

}
#EndRegion '.\Public\New-HuduRackStorageItem.ps1' 103
#Region '.\Public\New-HuduRelation.ps1' -1

function New-HuduRelation {
    <#
    .SYNOPSIS
    Create a Relation

    .DESCRIPTION
    Uses Hudu API to create relationships between objects

    .PARAMETER Description
    Give a description to the relation so you know why two things are related

    .PARAMETER FromableType
    The type of the FROM relation (Asset, Website, Procedure, AssetPassword, Company, Article)

    .PARAMETER FromableID
    The ID of the FROM relation

    .PARAMETER ToableType
    The type of the TO relation (Asset, Website, Procedure, AssetPassword, Company, Article)

    .PARAMETER ToableID
    The ID of the TO relation

    .PARAMETER IsInverse
    When a relation is created, it will also create another relation that is the inverse. When this is true, this relation is the inverse.

    .EXAMPLE
    An example

    .NOTES
    General notes
    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [String]$Description,

        [Parameter(Mandatory = $true)]
        [Alias('fromable_type')]
        [ValidateScript({Assert-AllowedObjectType -InputType $_ -AllowedCanonicals @(
                "VlanZone", "Vlan", "Procedure", "Website", "RackStorage", "Network", "IpAddress", "Article", "Company", "Asset", "AssetPassword"
        )})]
        [String]$FromableType,

        [Alias('fromable_id')]
        [int]$FromableID,

        [Alias('toable_type')]
        [ValidateScript({Assert-AllowedObjectType -InputType $_ -AllowedCanonicals @(
                "VlanZone", "Vlan", "Procedure", "Website", "RackStorage", "Network", "IpAddress", "Article", "Company", "Asset", "AssetPassword"
        )})]        
        [String]$ToableType,

        [Alias('toable_id')]
        [int]$ToableID,

        [Alias('is_inverse')]
        [string]$IsInverse
    )

    $Relation = [ordered]@{relation = [ordered]@{} }

    $Relation.relation.add('fromable_type', "$(Get-ObjectTypeFromCononical -inputData $FromableType)")
    $Relation.relation.add('fromable_id', $FromableID)
    $Relation.relation.add('toable_type', "$(Get-ObjectTypeFromCononical -inputData $ToableType)")
    $Relation.relation.add('toable_id', $ToableID)

    if ($Description) {
        $Relation.relation.add('description', $Description)
    }

    if ($ISInverse) {
        $Relation.relation.add('is_inverse', $ISInverse)
    }

    $JSON = $Relation | ConvertTo-Json -Depth 100

    if ($PSCmdlet.ShouldProcess($FromableType)) {
        Invoke-HuduRequest -Method post -Resource '/api/v1/relations' -Body $JSON
    }
}
#EndRegion '.\Public\New-HuduRelation.ps1' 81
#Region '.\Public\New-HuduUpload.ps1' -1

function New-HuduUpload {
    <#
    .SYNOPSIS
    Create a Upload

    .DESCRIPTION
    Uses Hudu API to upload a file for use in an asset. RecordType can be of 'asset','website','procedure','assetpassword','comapny','article'.

    .PARAMETER FilePath
    Path to the file

    .PARAMETER RecordId
    Record id to associate with the Upload

    .PARAMETER RecordType
    Record type to associate with the Upload

    .EXAMPLE
    New-HuduUpload -FilePath 'c:\path\to\file.png' -RecordId 1 -RecordType 'asset'

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [Alias('record_id','recordid','uploadableid')]
        [int]$uploadable_id,

        [Parameter(Mandatory)]
        [Alias('record_type','recordtype','uploadabletype')]
        [ValidateScript({Assert-AllowedObjectType -InputType $_ -AllowedCanonicals @(
                "VlanZone", "Vlan", "Procedure", "Website", "RackStorage", "Network", "IpAddress", "Article", "Company", "Asset", "AssetPassword","IpAddress"
        )})]
        [string]$uploadable_type
    )

    $File = Get-Item -LiteralPath $FilePath
    if (-not $File) { throw "File not found!" }
    
    $form = @{
        file = $File
        "upload[uploadable_id]" = $uploadable_id
        "upload[uploadable_type]" = $uploadable_type
    }

    if ($PSCmdlet.ShouldProcess($File.FullName)) {
        Invoke-HuduRequest -Method POST -Resource '/api/v1/uploads' -Form $form
    }
}
#EndRegion '.\Public\New-HuduUpload.ps1' 52
#Region '.\Public\New-HuduVLAN.ps1' -1

function New-HuduVLAN {
<#
.SYNOPSIS
Create a new VLAN in Hudu.

.DESCRIPTION
Creates a VLAN under a specified company. Requires a unique VLAN Id (between 4 and 4094).
Optionally associates role, status, or VLAN Zone.

.PARAMETER Name
The name of the VLAN.

.PARAMETER CompanyId
The company identifier to associate with this VLAN.

.PARAMETER VLANId
The numeric VLAN Id (between 4 and 4094).

.PARAMETER Description
Optional description text.

.PARAMETER RoleListItemID
Optional Id of the role list item to associate.

.PARAMETER StatusListItemID
Optional Id of the status list item to associate.

.PARAMETER VLANZoneId
Optional VLAN Zone Id to associate.

.PARAMETER Archived
Whether the VLAN should be archived upon creation ("true"/"false"). Defaults to "false".

.EXAMPLE
New-HuduVLAN -Name "VLAN-200" -CompanyId 1 -VLANId 200 -Description "Internal traffic"
#>    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [int]$CompanyId,
        [Parameter(Mandatory)][ValidateRange(4,4094)][int]$VLANId,
        [string]$Description,
        [int]$RoleListItemID,
        [int]$StatusListItemID,
        [int]$VLANZoneId,
        [ValidateSet("true","false")][string]$Archived='false'
    )

    $vlan = @{name=$Name; company_id = $CompanyId}
    if ($Description) {
        $vlan['description']=$Description
    }
    if ($RoleListItemID) {
        $vlan['role_list_item_id']=$RoleListItemID
    }
    if ($StatusListItemID) {
        $vlan['status_list_item_id']=$StatusListItemID
    }
    if ($VLANId) {
        $vlan['vlan_id']=$VLANId
    }
    if ($VLANZoneId) {
        $vlan['vlan_zone_id']=$VLANZoneId
    }
    if ($Archived) {
        $vlan['archived']=$Archived
    }
      

    $payload = @{
        vlan = $vlan
    } | ConvertTo-Json -Depth 10
    try {
        $res = Invoke-HuduRequest -Method POST -Resource "/api/v1/vlans" -Body $payload
        return $res
    } catch {
        Write-Warning "Failed to create vlan '$Name'"
        return $null
    }
}
#EndRegion '.\Public\New-HuduVLAN.ps1' 81
#Region '.\Public\New-HuduVLANZone.ps1' -1

function New-HuduVLANZone {
<#
.SYNOPSIS
Create a new VLAN Zone in Hudu.

.DESCRIPTION
Creates a VLAN Zone under a specified company, with VLAN Id ranges and optional description. 
VLAN ranges must be expressed as "start-end" and may be comma-separated.

.PARAMETER Name
The name of the VLAN Zone.

.PARAMETER CompanyId
The company identifier to associate with this VLAN Zone.

.PARAMETER VLANIdRanges
VLAN Id ranges string (e.g. "1-4", "200-300,400-450").

.PARAMETER Description
Optional description text.

.PARAMETER Archived
Whether the VLAN Zone should be archived upon creation ("true"/"false"). Defaults to "false".

.EXAMPLE
New-HuduVLANZone -Name "East Coast Zone" -CompanyId 1 -VLANIdRanges "200-300" -Description "Datacenter VLANs"
#>    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [int]$CompanyId,
        # VLAN ranges: "1-4", "200-300,400-450", etc.
        [ValidatePattern('^([1-9][0-9]{0,3}-[1-9][0-9]{0,3})(,([1-9][0-9]{0,3}-[1-9][0-9]{0,3}))*$')]
        [string]$VLANIdRanges,
        [string]$Description,
        [ValidateSet("true","false")][string]$Archived='false'
    )

    $vlan_zone = @{name=$Name; company_id = $CompanyId}
    if ($Description) {
        $vlan_zone['description']=$Description
    }
    if ($VLANIdRanges) {
        $vlan_zone['vlan_id_ranges']=$VLANIdRanges
    }
    if ($Archived) {
        $vlan_zone['archived']=$Archived
    }
   
    $payload = @{
        vlan_zone = $vlan_zone
    } | ConvertTo-Json -Depth 10
    try {
        $res = Invoke-HuduRequest -Method POST -Resource "/api/v1/vlan_zones" -Body $payload
        return $res
    } catch {
        Write-Warning "Failed to create vlan zone '$Name'"
        return $null
    }
}
#EndRegion '.\Public\New-HuduVLANZone.ps1' 61
#Region '.\Public\New-HuduWebsite.ps1' -1

function New-HuduWebsite {
    <#
    .SYNOPSIS
    Create a Website

    .DESCRIPTION
    Uses Hudu API to create a website

    .PARAMETER Name
    Website name (e.g. https://domain.com)

    .PARAMETER Notes
    Used to add additional notes to a website

    .PARAMETER Paused
    When true, website monitoring is paused

    .PARAMETER CompanyId
    Used to associate website with company

    .PARAMETER DisableDNS
    When true, dns monitoring is paused.

    .PARAMETER DisableSSL
    When true, ssl cert monitoring is paused.

    .PARAMETER DisableWhois
    When true, whois monitoring is paused.

    .PARAMETER EnableDMARC
    When true, DMARC monitoring is enabled.
    
    .PARAMETER EnableDKIM
    When true, DKIM monitoring is enabled.
    
    .PARAMETER EnableSPF
    When true, SPF monitoring is enabled.

    .PARAMETER Slug
    Url identifier

    .EXAMPLE
    New-HuduWebsite -CompanyId 1 -Name https://domain.com

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [String]$Name,

        [String]$Notes = '',

        [String]$Paused = '',

        [Alias('company_id')]
        [Parameter(Mandatory = $true)]
        [Int]$CompanyId,

        [Alias('disable_dns')]
        [String]$DisableDNS = '',

        [Alias('disable_ssl')]
        [String]$DisableSSL = '',

        [Alias('disable_whois')]
        [String]$DisableWhois = '',

        [Alias('enable_dmarc')]
        [String]$EnableDMARC = '',

        [Alias('enable_dkim')]
        [String]$EnableDKIM = '',

        [Alias('enable_spf')]
        [String]$EnableSPF = '',

        [string]$Slug
    )

    $Website = [ordered]@{website = [ordered]@{} }

    $Website.website.add('name', $Name)

    if ($Notes) {
        $Website.website.add('notes', $Notes)
    }

    if ($Paused) {
        $Website.website.add('paused', $Paused)
    }

    $Website.website.add('company_id', $CompanyId)

    if ($DisableDNS) {
        $Website.website.add('disable_dns', $DisableDNS)
    }

    if ($DisableSSL) {
        $Website.website.add('disable_ssl', $DisableSSL)
    }

    if ($DisableWhois) {
        $Website.website.add('disable_whois', $DisableWhois)
    }

    if ($Slug) {
        $Website.website.add('slug', $Slug)
    }

    if ($EnableDMARC) {
        $Website.website.add('enable_dmarc_tracking', $EnableDMARC)
    }

    if ($EnableDKIM) {
        $Website.website.add('enable_dkim_tracking', $EnableDKIM)
    }

    if ($EnableSPF) {
        $Website.website.add('enable_spf_tracking', $EnableSPF)
    }

    $JSON = $Website | ConvertTo-Json

    if ($PSCmdlet.ShouldProcess($Name)) {
        Invoke-HuduRequest -Method post -Resource '/api/v1/websites' -Body $JSON
    }
}
#EndRegion '.\Public\New-HuduWebsite.ps1' 128
#Region '.\Public\Remove-HuduAPIKey.ps1' -1

function Remove-HuduAPIKey {
    <#
    .SYNOPSIS
    Remove API key

    .DESCRIPTION
    Unsets the variable for the Hudu API Key

    .EXAMPLE
    Remove-HuduAPIKey

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param()

    if ($PSCmdlet.ShouldProcess('API Key')) {
        Remove-Variable -Name 'Int_HuduAPIKey' -Scope script -Force
    }
}
#EndRegion '.\Public\Remove-HuduAPIKey.ps1' 20
#Region '.\Public\Remove-HuduArticle.ps1' -1

function Remove-HuduArticle {
    <#
    .SYNOPSIS
    Delete a Knowledge Base Article

    .DESCRIPTION
    Uses Hudu API to remove a KB article

    .PARAMETER Id
    Id of the requested article

    .EXAMPLE
    Remove-HuduArticle -Id 1

    .NOTES
    General notes
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    Param (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [Int]$Id
    )
    process {
        if ($PSCmdlet.ShouldProcess($Id)) {
            Invoke-HuduRequest -Method delete -Resource "/api/v1/articles/$Id"
        }
    }
}
#EndRegion '.\Public\Remove-HuduArticle.ps1' 29
#Region '.\Public\Remove-HuduAsset.ps1' -1

function Remove-HuduAsset {
    <#
    .SYNOPSIS
    Delete an Asset

    .DESCRIPTION
    Uses Hudu API to remove an Asset from a company

    .PARAMETER Id
    Id of the requested Asset

    .PARAMETER CompanyId
    Id of the requested parent Company

    .EXAMPLE
    Remove-HuduAsset -CompanyId 1 -Id 1

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    Param (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [Int]$Id,
        [Alias('company_id')]
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [Int]$CompanyId
    )

    process {
        if ($PSCmdlet.ShouldProcess($Id)) {
            Invoke-HuduRequest -Method delete -Resource "/api/v1/companies/$CompanyId/assets/$Id"
        }
    }
}
#EndRegion '.\Public\Remove-HuduAsset.ps1' 34
#Region '.\Public\Remove-HuduBaseURL.ps1' -1

function Remove-HuduBaseURL {
    <#
    .SYNOPSIS
    Remove base URL

    .DESCRIPTION
    Unsets the Hudu Base URL variable

    .EXAMPLE
    Remove-HuduBaseURL

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param()
    if ($PSCmdlet.ShouldProcess('Base URL')) {
        Remove-Variable -Name 'Int_HuduBaseURL' -Scope script -Force
    }
}
#EndRegion '.\Public\Remove-HuduBaseURL.ps1' 19
#Region '.\Public\Remove-HuduCompany.ps1' -1

function Remove-HuduCompany {
    <#
    .SYNOPSIS
    Delete a Website

    .DESCRIPTION
    Uses Hudu API to delete a company

    .PARAMETER Id
    Id of the Company to delete

    .EXAMPLE
    Remove-HuduCompany -Id 1

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    Param (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [Int]$Id
    )

    process {
        if ($PSCmdlet.ShouldProcess($Id)) {
            Invoke-HuduRequest -Method delete -Resource "/api/v1/companies/$Id"
        }
    }
}
#EndRegion '.\Public\Remove-HuduCompany.ps1' 28
#Region '.\Public\Remove-HuduCustomHeaders.ps1' -1

function Remove-HuduCustomHeaders {
    <#
    .SYNOPSIS
    Remove Custom Headers that are injected into each request

    .DESCRIPTION
    Unsets the Hudu Custom Header variable

    .EXAMPLE
    Remove-HuduCustomHeaders

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param()
    if ($PSCmdlet.ShouldProcess('Custom Headers')) {
        Remove-Variable -Name 'Int_HuduCustomHeaders' -Scope script -Force
    }
}
#EndRegion '.\Public\Remove-HuduCustomHeaders.ps1' 19
#Region '.\Public\Remove-HuduFlag.ps1' -1

function Remove-HuduFlag {
<#
.SYNOPSIS
Deletes a Flag.

.DESCRIPTION
Deletes a Flag by ID. This is destructive and cannot be undone (unless Hudu provides recovery).
Supports ShouldProcess for -WhatIf / -Confirm.

.PARAMETER Id
The Flag ID to delete.

.EXAMPLE
Remove-HuduFlag -Id 77

.EXAMPLE
Get-HuduFlags -flagable_type Company -flagable_id 123 | Remove-HuduFlag -WhatIf

.NOTES
API Endpoint: DELETE /api/v1/flags/{id}
#>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName)]
        [Alias('FlagId')]
        [int]$Id
    )

    process {
        if ($PSCmdlet.ShouldProcess("Flag Id=$Id", "Delete")) {
            Invoke-HuduRequest -Method DELETE -Resource "/api/v1/flags/$Id" | Out-Null
        }
    }
}
#EndRegion '.\Public\Remove-HuduFlag.ps1' 36
#Region '.\Public\Remove-HuduFlagType.ps1' -1

function Remove-HuduFlagType {
<#
.SYNOPSIS
Deletes a Flag Type.

.DESCRIPTION
Deletes a Flag Type by ID. This may fail if the Flag Type is in use by existing Flags.
Supports ShouldProcess for -WhatIf / -Confirm.

.PARAMETER Id
The Flag Type ID to delete.

.EXAMPLE
Remove-HuduFlagType -Id 12

.EXAMPLE
Remove-HuduFlagType -Id 12 -WhatIf

.NOTES
API Endpoint: DELETE /api/v1/flag_types/{id}
#>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FlagTypeId')]
        [int]$Id
    )

    process {
        if ($PSCmdlet.ShouldProcess("Flag Type Id=$Id", "Delete")) {
            Invoke-HuduRequest -Method DELETE -Resource "/api/v1/flag_types/$Id" | Out-Null
            return $true
        }
    }
}
#EndRegion '.\Public\Remove-HuduFlagType.ps1' 37
#Region '.\Public\Remove-HuduIPAddress.ps1' -1

function Remove-HuduIPAddress {
<#
.SYNOPSIS
Delete a Hudu network.

.DESCRIPTION
Deletes one Hudu IPAM IP address objects.

.PARAMETER Id
IP address record ID to retrieve (exact match).

#>    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Id
    )

    try {
        Invoke-HuduRequest -Method DELETE -Resource "/api/v1/ip_addresses/$Id"
        Write-Host "Successfully deleted address ID $Id" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to delete address ID $Id"
    }
}
#EndRegion '.\Public\Remove-HuduIPAddress.ps1' 26
#Region '.\Public\Remove-HuduLabel.ps1' -1

function Remove-HuduLabel {
<#
.SYNOPSIS
Deletes a Label.

.DESCRIPTION
Deletes a Label by ID. Supports ShouldProcess for -WhatIf / -Confirm.

.PARAMETER Id
The Label ID to delete.

.EXAMPLE
Remove-HuduLabel -Id 77

.EXAMPLE
Get-HuduLabels -Labelable_Type Asset -Labelable_Id 123 | Remove-HuduLabel -WhatIf

.NOTES
API Endpoint: DELETE /api/v1/labels/{id}
#>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('LabelId','label_id')]
        [int]$Id
    )

    process {
        if ($PSCmdlet.ShouldProcess("Label Id=$Id", "Delete")) {
            Invoke-HuduRequest -Method DELETE -Resource "/api/v1/labels/$Id" | Out-Null
            return $true
        }
    }
}
#EndRegion '.\Public\Remove-HuduLabel.ps1' 36
#Region '.\Public\Remove-HuduLabelType.ps1' -1

function Remove-HuduLabelType {
<#
.SYNOPSIS
Deletes a Label Type.

.DESCRIPTION
Deletes a Label Type by ID. This may fail if the Label Type is in use by existing Labels.
Supports ShouldProcess for -WhatIf / -Confirm.

.PARAMETER Id
The Label Type ID to delete.

.EXAMPLE
Remove-HuduLabelType -Id 12

.EXAMPLE
Remove-HuduLabelType -Id 12 -WhatIf

.NOTES
API Endpoint: DELETE /api/v1/label_types/{id}
#>

    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('LabelTypeId','label_type_id')]
        [int]$Id
    )

    process {
        if ($PSCmdlet.ShouldProcess("Label Type Id=$Id", "Delete")) {
            Invoke-HuduRequest -Method DELETE -Resource "/api/v1/label_types/$Id" | Out-Null
            return $true
        }
    }
}
#EndRegion '.\Public\Remove-HuduLabelType.ps1' 37
#Region '.\Public\Remove-HuduList.ps1' -1

function Remove-HuduList {
    <#
    .SYNOPSIS
    Delete a Hudu List

    .DESCRIPTION
    Calls the Hudu API to delete a List by ID.

    .PARAMETER Id
    ID of the list to delete

    .EXAMPLE
    Remove-HuduList -Id 789 -WhatIf

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Id
    )

    try {
        Invoke-HuduRequest -Method DELETE -Resource "/api/v1/lists/$Id"
        Write-Host "Successfully deleted list ID $Id" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to delete list ID $Id"
    }
    
}
#EndRegion '.\Public\Remove-HuduList.ps1' 30
#Region '.\Public\Remove-HuduMagicDash.ps1' -1

function Remove-HuduMagicDash {
    <#
    .SYNOPSIS
    Delete a Magic Dash Item

    .DESCRIPTION
    Uses Hudu API to remove Magic Dash by Id or Title and Company Name

    .PARAMETER Title
    Title of the Magic Dash

    .PARAMETER CompanyName
    Company Name

    .PARAMETER Id
    Id of the Magic Dash

    .EXAMPLE
    Remove-HuduMagicDash -Id 1

    .EXAMPLE
    Remove-HuduMagicDash -Title 'Microsoft 365' -CompanyName 'AcmeCorp'

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Id')]
    Param (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true, ParameterSetName = 'TitleCompany')]
        [String]$Title,

        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true, ParameterSetName = 'TitleCompany')]
        [Alias('company_name')]
        [String]$CompanyName,

        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true, ParameterSetName = 'Id')]
        [int]$Id
    )

    process {
        if ($id) {
            if ($PSCmdlet.ShouldProcess($Id)) {
                $null = Invoke-HuduRequest -Method delete -Resource "/api/v1/magic_dash/$Id"
            }
        } else {
            $MagicDash = @{}

            $MagicDash.add('title', $Title)
            $MagicDash.add('company_name', $CompanyName)

            $JSON = $MagicDash | ConvertTo-Json

            if ($PSCmdlet.ShouldProcess("$Company - $Title")) {
                $null = Invoke-HuduRequest -Method delete -Resource '/api/v1/magic_dash' -Body $JSON
            }
        }
    }
}
#EndRegion '.\Public\Remove-HuduMagicDash.ps1' 57
#Region '.\Public\Remove-HuduNetwork.ps1' -1

function Remove-HuduNetwork {
<#
.SYNOPSIS
Delete a Hudu network.

.DESCRIPTION
Deletes a Hudu IPAM Network from a Company. Writes a success message if the
deletion is acknowledged by the API, otherwise writes a warning.

.PARAMETER Id
The unique network ID to delete. (Required)

.EXAMPLE
Remove-HuduNetwork -Id 123
#>    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Id
    )

    try {
        Invoke-HuduRequest -Method DELETE -Resource "/api/v1/networks/$Id"
        Write-Host "Successfully deleted network ID $Id" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to delete network ID $Id"
    }
}
#EndRegion '.\Public\Remove-HuduNetwork.ps1' 29
#Region '.\Public\Remove-HuduPassword.ps1' -1

function Remove-HuduPassword {
    <#
    .SYNOPSIS
    Delete a Password

    .DESCRIPTION
    Uses Hudu API to remove asset password

    .PARAMETER Id
    Id of the password

    .EXAMPLE
    Remove-HuduPassword -Id 1

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    Param (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [Int]$Id
    )
    process {
        if ($PSCmdlet.ShouldProcess($Id)) {
            Invoke-HuduRequest -Method delete -Resource "/api/v1/asset_passwords/$Id"
        }
    }
}
#EndRegion '.\Public\Remove-HuduPassword.ps1' 27
#Region '.\Public\Remove-HuduPasswordFolder.ps1' -1

function Remove-HuduPasswordFolder {
    <#
    .SYNOPSIS
    Delete a PasswordFolder by ID

    .DESCRIPTION
    Uses Hudu API to remove passwordfolder

    .PARAMETER Id
    Id of the passwordfolder

    .EXAMPLE
    Remove-HuduPasswordFolder -Id 1

    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [Int]$Id
    )
    process {
        Invoke-HuduRequest -Method delete -Resource "/api/v1/password_folders/$Id"
    }
}
#EndRegion '.\Public\Remove-HuduPasswordFolder.ps1' 25
#Region '.\Public\Remove-HuduPhoto.ps1' -1

function Remove-HuduPhoto {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('PhotoId')]
        [int]$Id
    )
    process {
        [version]$script:Version = $script:Version ?? [version]((Get-HuduAppInfo).version)

        if ($script:Version -lt [version]'2.41.0') {
            write-warning "Remove-HuduPhoto: Hudu version $($script:Version) is below 2.41.0; Skipping."
            return $false
        }
        if ($PSCmdlet.ShouldProcess("Photo $Id", "Delete permanently")) {
            try {
                Invoke-HuduRequest -Method DELETE -Resource "/api/v1/photos/$Id"
                return $true
            } catch {
                Write-Warning "Failed to delete photo ID $Id"
                return $false
            }
        }
    }
}
#EndRegion '.\Public\Remove-HuduPhoto.ps1' 26
#Region '.\Public\Remove-HuduProcedure.ps1' -1

function Remove-HuduProcedure {
    <#
    .SYNOPSIS
    Delete a procedure

    .DESCRIPTION
    Permanently deletes a procedure by ID.

    .PARAMETER Id
    ID of the procedure to delete

    .EXAMPLE
    Remove-HuduProcedure -Id 7
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)] [int]$Id
    )
    $response = $null
    try {
        $response = Invoke-HuduRequest -Method DELETE -Resource "/api/v1/procedures/$Id"
        Write-Host "Successfully deleted procedure ID $Id" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to delete procedure ID $Id"
    }
    return $response
}
#EndRegion '.\Public\Remove-HuduProcedure.ps1' 28
#Region '.\Public\Remove-HuduProcedureTask.ps1' -1

function Remove-HuduProcedureTask {
    <#
    .SYNOPSIS
    Delete a procedure task

    .DESCRIPTION
    Permanently deletes a procedure task by ID.

    .PARAMETER Id
    ID of the task to delete

    .EXAMPLE
    Remove-HuduProcedureTask -Id 88
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)] [int]$Id
    )

    if ($PSCmdlet.ShouldProcess("Procedure Task ID $Id", "Delete")) {
        try {
            Invoke-HuduRequest -Method DELETE -Resource "/api/v1/procedure_tasks/$Id"
            Write-Host "Successfully deleted task ID $Id" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to delete task ID $Id"
        }
    }
}
#EndRegion '.\Public\Remove-HuduProcedureTask.ps1' 29
#Region '.\Public\Remove-HuduRackStorage.ps1' -1

function Remove-HuduRackStorage {
    <#
    .SYNOPSIS
    Remove a single Rack Storage from Hudu.

    .DESCRIPTION
    Calls the Hudu API to delete a Rack Storage by its ID. This operation is permanent and cannot be undone.

    .PARAMETER Id
    The ID of the Rack Storage to delete.

    .EXAMPLE
    Remove-HuduRackStorage -Id 123

    Deletes the Rack Storage with ID 123.

    .NOTES
    API Endpoint: DELETE /api/v1/rack_storages/{id}
    Requires confirmation before deletion unless -Confirm:$false is specified.
    #>
    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][int]$Id
    )

    if ($PSCmdlet.ShouldProcess("Rack Storage $Id", "Delete")) {
        $Request = @{
            Method   = 'DELETE'
            Resource = "/api/v1/rack_storages/$Id"
        }

        Invoke-HuduRequest @Request
    }
}
#EndRegion '.\Public\Remove-HuduRackStorage.ps1' 36
#Region '.\Public\Remove-HuduRackStorageItem.ps1' -1

function Remove-HuduRackStorageItem {
    [CmdletBinding()]
    <#
    .SYNOPSIS
    Remove a single rack storage item from Hudu

    .DESCRIPTION
    Calls Hudu API to remove a rack storage item by Id

    .PARAMETER Id
    Id of rack storage item to delete from Hudu

    .EXAMPLE
    Remove-HuduRackStorageItem -Id 456

    Deletes the Rack Storage Item with ID 456 from Hudu.

    .NOTES
    API Endpoint: DELETE /api/v1/rack_storage_items/{id}
    #>
    param (
        [Parameter(Mandatory)]
        [int]$Id
    )

    if ($PSCmdlet.ShouldProcess("RackStorageItem $Id", "Delete")) {
        $HuduRequest = @{
            Method   = 'DELETE'
            Resource = "/api/v1/rack_storage_items/$Id"
        }

        Invoke-HuduRequest @HuduRequest
    }
}
#EndRegion '.\Public\Remove-HuduRackStorageItem.ps1' 35
#Region '.\Public\Remove-HuduRelation.ps1' -1

function Remove-HuduRelation {
    <#
    .SYNOPSIS
    Delete a Relation

    .DESCRIPTION
    Uses Hudu API to delete object relationships

    .PARAMETER Id
    Id of the requested Relation

    .EXAMPLE
    Remove-HuduRelation -Id 1

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    Param (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [Int]$Id
    )

    process {
        if ($PSCmdlet.ShouldProcess($Id)) {
            Invoke-HuduRequest -Method delete -Resource "/api/v1/relations/$Id"
        }
    }
}
#EndRegion '.\Public\Remove-HuduRelation.ps1' 28
#Region '.\Public\Remove-HuduUpload.ps1' -1

function Remove-HuduUpload {
    <#
    .SYNOPSIS
    Delete an Upload by ID

    .DESCRIPTION
    Calls Hudu API to delete uploads by specifying the ID value

    .EXAMPLE
    Remove-HuduUpload

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    Param(
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [Int]$Id
    )

    process {
        if ($PSCmdlet.ShouldProcess($Id)) {
            Invoke-HuduRequest -Method delete -Resource "/api/v1/uploads/$Id"
        }
    }
    
}
#EndRegion '.\Public\Remove-HuduUpload.ps1' 26
#Region '.\Public\Remove-HuduVLAN.ps1' -1

function Remove-HuduVLAN {
<#
.SYNOPSIS
Delete a VLAN from Hudu.

.DESCRIPTION
Removes the VLAN with the specified Id. Supports `-WhatIf`/`-Confirm`.

.PARAMETER Id
The Id of the VLAN to delete.

.EXAMPLE
Remove-HuduVLAN -Id 45 -Confirm:$false
#>    
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)] [int]$Id
    )
    $response = $null
    try {
        $response = Invoke-HuduRequest -Method DELETE -Resource "/api/v1/vlans/$Id"
        Write-Host "Successfully deleted vlan ID $Id" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to delete vlan ID $Id"
    }
    return $response
}
#EndRegion '.\Public\Remove-HuduVLAN.ps1' 28
#Region '.\Public\Remove-HuduVLANZone.ps1' -1

function Remove-HuduVLANZone {
<#
.SYNOPSIS
Delete a VLAN Zone from Hudu.

.DESCRIPTION
Removes the VLAN Zone with the specified Id. Supports `-WhatIf`/`-Confirm`.

.PARAMETER Id
The Id of the VLAN Zone to delete.

.EXAMPLE
Remove-HuduVLANZone -Id 12 -Confirm:$false
#>    
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)] [int]$Id
    )
    $response = $null
    try {
        $response = Invoke-HuduRequest -Method DELETE -Resource "/api/v1/vlan_zones/$Id"
        Write-Host "Successfully deleted vlan zone ID $Id" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to delete vlan zone ID $Id"
    }
    return $response
}
#EndRegion '.\Public\Remove-HuduVLANZone.ps1' 28
#Region '.\Public\Remove-HuduWebsite.ps1' -1

function Remove-HuduWebsite {
    <#
    .SYNOPSIS
    Delete a Website

    .DESCRIPTION
    Uses Hudu API to delete a website

    .PARAMETER Id
    Id of the requested Website

    .EXAMPLE
    Remove-HuduWebsite -Id 1

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    Param (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [Int]$Id
    )

    process {
        if ($PSCmdlet.ShouldProcess($Id)) {
            Invoke-HuduRequest -Method delete -Resource "/api/v1/websites/$Id"
        }
    }
}
#EndRegion '.\Public\Remove-HuduWebsite.ps1' 28
#Region '.\Public\Save-HuduExports.ps1' -1


function Save-HuduExports {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [long]$Id,
        [Parameter()]
        [string]$OutDir = '.'
    )

    $OutDir = [string]::IsNullOrWhiteSpace($OutDir) ? (Get-Location).Path : $OutDir
    $OutDir = (New-Item -ItemType Directory -Path $OutDir -Force).FullName
    $exports = $(if ($null -ne $Id) {@(Get-HuduExports -id $id)} else {@(Get-HuduExports)})

    if (-not $exports -or $exports.Count -eq 0) {Write-Warning "No exports available."; return;}
    $HuduAPIKey = Get-HuduApiKey
    $Headers = @{'x-api-key' = (New-Object PSCredential 'user', $HuduAPIKey).GetNetworkCredential().Password;}

    $files = @(); $fileIDX = 0;
    foreach ($export in $exports) {
        $fileIDX++; $downloadedFile = $null;
        $fileName = $export.file_name ?? "export-$($export.id)$(if ($export.is_pdf) { '.pdf' } else { '.csv' })"

        if (-not $export.download_url -or [string]::isnullorempty($export.download_url)) {
            Write-Warning "Export id $($export.id) has no download_url yet (status=$($export.status)). Skipping."
            write-host "$($($export | convertto-json -depth 99).ToSTring())"
            continue
        }

        $outPath = Join-Path $OutDir $fileName

        if ($PSCmdlet.ShouldProcess($outPath, "Download export id $exId")) {
            Invoke-WebRequest -Uri $export.download_url -headers $headers -OutFile $outPath -MaximumRedirection 10 | Out-Null
        }
        $downloadedFile = $(Get-Item -LiteralPath $outPath)
        Write-Host "downloaded $fileName to $($downloadedFile) ($fileIDX of $($exports.count))"
        $files+=$($downloadedFile)
    }
    return $files
}
#EndRegion '.\Public\Save-HuduExports.ps1' 41
#Region '.\Public\Set-HapiErrorsDirectory.ps1' -1

function Set-HapiErrorsDirectory {
    param(
        [Parameter()][string]$Path=$null,
        [Parameter()][bool]$skipRetry=$false,
        [Parameter()][ValidateSet("Black","DarkBlue","DarkGreen","DarkCyan","DarkRed","DarkMagenta","DarkYellow","Gray","DarkGray","Blue","Green","Cyan","Red","Magenta","Yellow","White",$null)]
        [string]$Color=$null)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = $script:HAPI_ERRORS_DIRECTORY ?? (Join-Path -Path ([Environment]::GetFolderPath('LocalApplicationData')) -ChildPath "$($("$(Get-HuduBaseURL)" -replace "https://",'') -replace "/",'')-errors")
    }
    if (!(Test-Path -Path $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
    try {
        $Path = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    } catch {
        $Path = $path
    }    
    $script:HAPI_ERRORS_DIRECTORY = $Path

    if ($null -ne $skipRetry) {
        $script:SKIP_HAPI_ERROR_RETRY = $skipRetry
    } else {
        $script:SKIP_HAPI_ERROR_RETRY = $script:SKIP_HAPI_ERROR_RETRY ?? $false
    }
    if ($Color -and @("Black","DarkBlue","DarkGreen","DarkCyan","DarkRed","DarkMagenta","DarkYellow","Gray","DarkGray","Blue","Green","Cyan","Red","Magenta","Yellow","White") -contains $Color) {
        $script:HAPI_ERROR_COLOR = $Color
    } else {
        $script:HAPI_ERROR_COLOR = $script:HAPI_ERROR_COLOR  ?? "DarkCyan"
    }
    return [pscustomobject]@{
        Path        = $script:HAPI_ERRORS_DIRECTORY
        SkipRetry   = $script:SKIP_HAPI_ERROR_RETRY
        Color       = $script:HAPI_ERROR_COLOR
    }
}
#EndRegion '.\Public\Set-HapiErrorsDirectory.ps1' 36
#Region '.\Public\Set-HuduArticle.ps1' -1

function Set-HuduArticle {
    <#
    .SYNOPSIS
    Update a Knowledge Base Article

    .DESCRIPTION
    Uses Hudu API to update KB Article

    .PARAMETER Name
    Name of the Article

    .PARAMETER Content
    Article Content

    .PARAMETER EnableSharing
    Set article to public and generate a URL

    .PARAMETER FolderId
    Used to associate article with folder

    .PARAMETER CompanyId
    Used to associate article with company

    .PARAMETER ArticleId
    Id of the requested article

    .PARAMETER Slug
    Url identifier

    .EXAMPLE
    Set-HuduArticle -ArticleId 1 -Name 'Article Name' -Content '<h1>New article contents</h1>'

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [String]$Name,

        [String]$Content,
        [switch]$EnableSharing,

        [Alias('folder_id')]
        [Nullable[int]]$FolderId,

        [Alias('company_id')]
        [Nullable[int]]$CompanyId,

        [Alias('article_id', 'id')]
        [Parameter(Mandatory = $true)]
        [Int]$ArticleId,

        [string]$Slug
    )
    
    $Object = Get-HuduArticles -Id $ArticleId
    $Article = [ordered]@{article = $Object.article }

    if ($Name) {
        $Article.article.name = $Name
    }
    
    if ($Content) {
        $Article.article.content = $Content
    }
    
    if ($PSBoundParameters.ContainsKey('FolderId')) {
        $Article.article.folder_id = $FolderId
    }

    if ($PSBoundParameters.ContainsKey('CompanyId')) {
        $Article.article.company_id = $CompanyId
    }

    if ($EnableSharing.IsPresent) {
        $Article.article.enable_sharing = $true
    }

    if ($Slug) {
        $Article.article.slug = $Slug
    }

    $JSON = $Article | ConvertTo-Json -Depth 10

    if ($PSCmdlet.ShouldProcess($Name)) {
        Invoke-HuduRequest -Method put -Resource "/api/v1/articles/$ArticleId" -Body $JSON
    }
}
#EndRegion '.\Public\Set-HuduArticle.ps1' 87
#Region '.\Public\Set-HuduArticleArchive.ps1' -1

function Set-HuduArticleArchive {
    <#
    .SYNOPSIS
    Archive/Unarchive a Knowledge Base Article

    .DESCRIPTION
    Uses Hudu API to archive or unarchive an article

    .PARAMETER Id
    Id of the requested article

    .PARAMETER Archive
    Boolean for archive status

    .EXAMPLE
    Set-HuduArticleArchive -Id 1 -Archive $true

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [Int]$Id,
        [Parameter(Mandatory = $true)]
        [Bool]$Archive
    )

    if ($Archive) {
        $Action = 'archive'
    } else {
        $Action = 'unarchive'
    }

    if ($PSCmdlet.ShouldProcess($Id)) {
        Invoke-HuduRequest -Method put -Resource "/api/v1/articles/$Id/$Action"
    }
}
#EndRegion '.\Public\Set-HuduArticleArchive.ps1' 37
#Region '.\Public\Set-HuduArticlePinned.ps1' -1

function Set-HuduArticlePinned {
    <#
    .SYNOPSIS
    Pins a Knowledge Base Article to the top of the list
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    Param (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [Int]$Id
    )
    process {
        if ($PSCmdlet.ShouldProcess($Id)) {
            $result = Invoke-HuduRequest -Method put -Resource "/api/v1/articles/$Id/pin"
            $result = $result.article ?? $result
            return $result
        }
    }
}
#EndRegion '.\Public\Set-HuduArticlePinned.ps1' 19
#Region '.\Public\Set-HuduArticleUnPinned.ps1' -1

function Set-HuduArticleUnPinned {
    <#
    .SYNOPSIS
    UnPins a Knowledge Base Article from the top of the list
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    Param (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [Int]$Id
    )
    process {
        if ($PSCmdlet.ShouldProcess($Id)) {
            $result = Invoke-HuduRequest -Method put -Resource "/api/v1/articles/$Id/unpin"
            $result = $result.article ?? $result
            return $result
        }
    }
}
#EndRegion '.\Public\Set-HuduArticleUnPinned.ps1' 19
#Region '.\Public\Set-HuduAsset.ps1' -1

function Set-HuduAsset {
    <#
    .SYNOPSIS
    Update an Asset

    .DESCRIPTION
    Uses Hudu API to update an Asset

    .PARAMETER Name
    Name of the Asset

    .PARAMETER CompanyId
    Company id of the Asset

    .PARAMETER AssetLayoutId
    Asset layout id

    .PARAMETER Fields
    List of fields

    .PARAMETER AssetId
    Id of the requested Asset

    .PARAMETER PrimarySerial
    Primary serial number

    .PARAMETER PrimaryMail
    Primary mail

    .PARAMETER PrimaryModel
    Primary model

    .PARAMETER PrimaryManufacturer
    Primary manufacturer

    .PARAMETER Slug
    Url identifier

    .PARAMETER ExistingAsset
    The asset as already returned by Get-HuduAssets. The update is built from it instead of fetching the asset again

    .EXAMPLE
    Set-HuduAsset -AssetId 1 -CompanyId 1 -Fields @(@{'field_name'='Field Value'})

    .EXAMPLE
    Get-HuduAssets -CompanyId 1 -AssetLayoutId 2 | ForEach-Object { Set-HuduAsset -Id $_.id -ExistingAsset $_ -Fields @(@{'field_name'='Field Value'}) }

    .NOTES
    General notes
    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [String]$Name,

        [Alias('company_id')]
        [Int]$CompanyId,

        [Alias('asset_layout_id')]
        [Int]$AssetLayoutId,

        [Array]$Fields,

        [Alias('asset_id','assetid')]
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, [int]::MaxValue)]
        [Int]$Id,
        
        [Alias('primary_serial')]
        [string]$PrimarySerial,

        [Alias('primary_mail')]
        [string]$PrimaryMail,

        [Alias('primary_model')]
        [string]$PrimaryModel,

        [Alias('primary_manufacturer')]
        [string]$PrimaryManufacturer,

        [string]$Slug,

        [object]$ExistingAsset
    )

    $Object = $(if ($ExistingAsset) { $ExistingAsset } else { Get-HuduAssets -id $Id }) | Select-Object name,asset_layout_id,company_id,slug,primary_serial,primary_model,primary_mail,id,primary_manufacturer,@{n='custom_fields';e={$_.fields | ForEach-Object {[pscustomobject]@{$_.label.replace(' ','_').tolower()= $_.value}}}}
    if ($Object) {
        $Asset = [ordered]@{asset = $Object }
        $CompanyId = $Object.company_id
    
        if ($Name) {
            $Asset.asset.name = $Name
        }
    
        if ($AssetLayoutId) {
            $Asset.asset.asset_layout_id = $AssetLayoutId
        }
        
        if ($PrimarySerial) {
            $Asset.asset.primary_serial = $PrimarySerial
        }
    
        if ($PrimaryMail) {
            $Asset.asset.primary_mail = $PrimaryMail
        }
    
        if ($PrimaryModel) {
            $Asset.asset.primary_model = $PrimaryModel
        }
    
        if ($PrimaryManufacturer) {
            $Asset.asset.primary_manufacturer = $PrimaryManufacturer
        }
    
        if ($Fields) {
            $Asset.asset.custom_fields = $Fields
        }
    
        if ($Slug) {
            $Asset.asset.slug = $Slug
        }
    
        $JSON = $Asset | ConvertTo-Json -Depth 10
    
        if ($PSCmdlet.ShouldProcess("ID: $($Asset.id) Name: $($Asset.Name)", "Set Hudu Asset")) {
            Invoke-HuduRequest -Method put -Resource "/api/v1/companies/$CompanyId/assets/$Id" -Body $JSON
        }
    } else {
    throw "A valid asset could not be found to update, please double check the ID and try again"
    }
}
#EndRegion '.\Public\Set-HuduAsset.ps1' 131
#Region '.\Public\Set-HuduAssetArchive.ps1' -1

function Set-HuduAssetArchive {
    <#
    .SYNOPSIS
    Archive/Unarchive an Asset

    .DESCRIPTION
    Uses Hudu API to archive or unarchive an asset

    .PARAMETER Id
    Id of the requested Asset

    .PARAMETER CompanyId
    Id of the requested parent company

    .PARAMETER Archive
    Boolean for archive status

    .EXAMPLE
    Set-HuduAssetArchive -Id 1 -CompanyId 1 -Archive $true

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [Int]$Id,
        [Alias('company_id')]
        [Parameter(Mandatory = $true)]
        [Int]$CompanyId,
        [Parameter(Mandatory = $true)]
        [Bool]$Archive
    )

    if ($Archive) {
        $Action = 'archive'
    } else {
        $Action = 'unarchive'
    }

    if ($PSCmdlet.ShouldProcess($Id)) {
        Invoke-HuduRequest -Method put -Resource "/api/v1/companies/$CompanyId/assets/$Id/$Action"
    }
}
#EndRegion '.\Public\Set-HuduAssetArchive.ps1' 43
#Region '.\Public\Set-HuduAssetLayout.ps1' -1

function Set-HuduAssetLayout {
    <#
    .SYNOPSIS
    Update an Asset Layout

    .DESCRIPTION
    Uses Hudu API to update an Asset Layout

    .PARAMETER Id
    Id of the requested Asset Layout

    .PARAMETER Name
    Name of the Asset Layout

    .PARAMETER Icon
    Icon class name, example: "fas fa-home"

    .PARAMETER Color
    Background color as a hex value, such as #000000, or a human-readable color
    name in a supported language. Alpha values are trimmed off.

    .PARAMETER IconColor
    Icon color as a hex value, such as #000000, or a human-readable color
    name in a supported language. Alpha values are trimmed off.

    .PARAMETER IncludePasswords
    Boolean to include passwords

    .PARAMETER IncludePhotos
    Boolean to include photos

    .PARAMETER IncludeComments
    Boolean to include comments

    .PARAMETER IncludeFiles
    Boolean to include files

    .PARAMETER PasswordTypes
    List of password types, separated with new line characters

    .PARAMETER Slug
    Url identifier

    .PARAMETER Fields
    Array of hashtable or custom objects representing layout fields. Most field types only require a label and type.
    Valid field types are: Text, RichText, Heading, CheckBox, Website (aka Link), Password (aka ConfidentialText), Number, Date, DropDown (deprecated), ListSelect (replacement for Dropdown), Embed, Email (aka CopyableText), Phone, AssetLink
    Field types are Case Sensitive as of Hudu V2.27 due to a known issue with asset type validation.

    .EXAMPLE
    Set-HuduAssetLayout -Id 12 -Name 'Test asset layout' -Icon 'fas fa-home' -IncludePassword $true

    .EXAMPLE
    Set-HuduAssetLayout -Id 12 -Color 'naranja' -IconColor '#ffffff'

    .EXAMPLE
    Set-HuduAssetLayout -Id 12 -SidebarFolderID 3

    .EXAMPLE
    Set-HuduAssetLayout -Id 12 -Fields @(
        @{label = 'Test field'; 'field_type' = 'Text'}
    )
    #>
    [CmdletBinding(SupportsShouldProcess)]
    # This will silence the warning for variables with Password in their name.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '')]
    Param (
        [Parameter(Mandatory = $true)]
        [Int]$Id,

        [String]$Name,

        [String]$Icon,

        [String]$Color,

        [Alias('icon_color')]
        [String]$IconColor,

        [Alias('include_passwords')]
        [bool]$IncludePasswords,

        [Alias('include_photos')]
        [bool]$IncludePhotos,

        [Alias('include_comments')]
        [bool]$IncludeComments,

        [Alias('include_files')]
        [bool]$IncludeFiles,

        [Alias('password_types')]
        [String]$PasswordTypes = '',
        
        [bool]$Active,

        [string]$Slug,

        [array]$Fields,
        [bool]$isLocation = $false
    )

    foreach ($field in $fields) {
        if ($field.show_in_list) { $field.show_in_list = [System.Convert]::ToBoolean($field.show_in_list) } else { $field.remove('show_in_list') }
        if ($field.required) { $field.required = [System.Convert]::ToBoolean($field.required) } else { $field.remove('required') }
        if ($field.expiration) { $field.expiration = [System.Convert]::ToBoolean($field.expiration) } else { $field.remove('expiration') }
        # A bug in versions of Hudu 2.27 and earlier can cause asset layouts to become corrupted if the field type value is not properly cased.
        switch ($field.'field_type') {
            'text'              { $field.'field_type' = 'Text' }
            'richtext'          { $field.'field_type' = 'RichText' }
            'heading'           { $field.'field_type' = 'Heading' }
            'checkbox'          { $field.'field_type' = 'CheckBox' }
            'number'            { $field.'field_type' = 'Number' }
            'date'              { $field.'field_type' = 'Date' }
            'dropdown'          { Write-Warning "Dropdown Field Types have been deprecated but still available via the API. Please use ListSelect types moving forward if possible. This is not a failure."; $field.'field_type' = 'Dropdown' }
            'embed'             { $field.'field_type' = 'Embed' }
            'phone'             { $field.'field_type' = 'Phone' }
            'email'             { $field.'field_type' = 'Email' }
            'copyabletext'      { $field.'field_type' = 'Email' }
            'address'           { $field.'field_type' = 'AddressData' }            
            'addressdata'       { $field.'field_type' = 'AddressData' }            
            'assettag'          { $field.'field_type' = 'AssetTag' }
            'assetlink'         { $field.'field_type' = 'AssetTag' }
            'website'           { $field.'field_type' = 'Website' }
            'link'              { $field.'field_type' = 'Website' }
            'password'          { $field.'field_type' = 'Password' }
            'divider'           { $field.'field_type' = 'Divider' }
            'seperator'          { $field.'field_type' = 'Divider' }
            'confidentialtext'  { $field.'field_type' = 'Password' }
            'listselect' { $field.'field_type' = 'ListSelect' }
            Default { throw "Invalid field type: $($field.'field_type') found in field $($field.name)" }
        }
    }
    $Object = Get-HuduAssetLayouts -id $Id

    $AssetLayout = [ordered]@{asset_layout = $Object }
    #$AssetLayout.asset_layout = $Object

    if ($Name) {
        $AssetLayout.asset_layout.name = $Name
    }
    
    if ($Icon) {
        $AssetLayout.asset_layout.icon = $Icon
    }

    if ($Color) {
        $AssetLayout.asset_layout.color = ConvertTo-HuduLabelColor -Color $Color
    }

    if ($IconColor) {
        $AssetLayout.asset_layout.icon_color = ConvertTo-HuduLabelColor -Color $IconColor
    }

    if ($Fields) {
        $AssetLayout.asset_layout.fields = $Fields
    }

    if ($IncludePasswords) {
        $AssetLayout.asset_layout.include_passwords = [System.Convert]::ToBoolean($IncludePasswords)
    }

    if ($IncludePhotos) {
        $AssetLayout.asset_layout.include_photos = [System.Convert]::ToBoolean($IncludePhotos)
    }

    if ($IncludeComments) {
        $AssetLayout.asset_layout.include_comments = [System.Convert]::ToBoolean($IncludeComments)
    }

    if ($IncludeFiles) {
        $AssetLayout.asset_layout.include_files = [System.Convert]::ToBoolean($IncludeFiles)
    }

    if ($PasswordTypes) {
        $AssetLayout.asset_layout.password_types = $PasswordTypes
    }

    if ($PSBoundParameters.ContainsKey('SidebarFolderID')) {
        $AssetLayout.asset_layout | Add-Member -MemberType NoteProperty -Name sidebar_folder_id -Force -Value $SidebarFolderID
    }

    if ($Slug) {
        $AssetLayout.asset_layout.slug = $Slug
    }
    if ($PSBoundParameters.ContainsKey('isLocation')){
        $AssetLayout.asset_layout.location = [System.Convert]::ToBoolean($isLocation)
    }

    if ($PSBoundParameters.ContainsKey('Active')){
        $AssetLayout.asset_layout.active = [System.Convert]::ToBoolean($Active)
    }

    $JSON = $AssetLayout | ConvertTo-Json -Depth 10

    if ($PSCmdlet.ShouldProcess($Id)) {
        Invoke-HuduRequest -Method put -Resource "/api/v1/asset_layouts/$Id" -Body $JSON
    }
}
#EndRegion '.\Public\Set-HuduAssetLayout.ps1' 199
#Region '.\Public\Set-HuduAssetLayoutField.ps1' -1

function Set-HuduAssetLayoutField {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$LayoutId,

        [Parameter(Mandatory)]
        [string]$FieldLabel,

        [Parameter(Mandatory)]
        [string]$PropertyName,

        [Parameter(Mandatory)]
        $PropertyValue
    )

    # 1. Get full layout
    $layout = Get-HuduAssetLayouts -layoutid $LayoutId
    if (-not $layout) {
        throw "Layout ID $LayoutId not found."
    }

    # 2. Convert PSCustomObject fields → Hashtables Hudu accepts
    $fields = foreach ($f in $layout.fields) {
        $ht = @{}
        foreach ($p in $f.PSObject.Properties) {
            # Preserve only non-empty values to match Hudu’s preferred formatting
            if ($null -ne $p.Value -and $p.Value -ne "") {
                $ht[$p.Name] = $p.Value
            }
        }
        $ht
    }

    # 3. Locate the field by label
    $target = $fields | Where-Object { $_.label -eq $FieldLabel }

    if (-not $target) {
        throw "Field '$FieldLabel' not found on layout $LayoutId."
    }

    # 4. Apply mutation
    $target[$PropertyName] = $PropertyValue

    # 5. Repost the entire layout using original layout properties
    $null = Set-HuduAssetLayout `
        -id $layout.id `
        -name $layout.name `
        -icon $layout.icon `
        -color $layout.color `
        -icon_color $layout.icon_color `
        -include_passwords $layout.include_passwords `
        -include_photos $layout.include_photos `
        -include_comments $layout.include_comments `
        -include_files $layout.include_files `
        -fields $fields

    # 6. Return updated object
    return Get-HuduAssetLayouts -layoutid $LayoutId
}
#EndRegion '.\Public\Set-HuduAssetLayoutField.ps1' 61
#Region '.\Public\Set-HuduCompany.ps1' -1

function Set-HuduCompany {
    <#
    .SYNOPSIS
    Update a company

    .DESCRIPTION
    Uses Hudu API to update a Company

    .PARAMETER Id
    Id of the requested company

    .PARAMETER Name
    Name of the company

    .PARAMETER Nickname
    Nickname of the company

    .PARAMETER CompanyType
    Company type

    .PARAMETER AddressLine1
    Address line 1

    .PARAMETER AddressLine2
    Address line 2

    .PARAMETER City
    City

    .PARAMETER State
    State

    .PARAMETER Zip
    Zip

    .PARAMETER CountryName
    Country name

    .PARAMETER PhoneNumber
    Phone number

    .PARAMETER FaxNumber
    Fax number

    .PARAMETER Website
    Webste

    .PARAMETER IdNumber
    Id number

    .PARAMETER ParentCompanyId
    Parent company id

    .PARAMETER Notes
    Company notes

    .PARAMETER Slug
    Url identifier

    .EXAMPLE
    Set-HuduCompany -Id 1 -Name 'New company name'

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [Int]$Id,

        [String]$Name,

        [String]$Nickname = '',

        [Alias('company_type')]
        [String]$CompanyType = '',

        [Alias('address_line_1')]
        [String]$AddressLine1 = '',

        [Alias('address_line_2')]
        [String]$AddressLine2 = '',

        [String]$City = '',

        [String]$State = '',

        [Alias('PostalCode', 'PostCode')]
        [String]$Zip = '',

        [Alias('country_name')]
        [String]$CountryName = '',

        [Alias('phone_number')]
        [String]$PhoneNumber = '',

        [Alias('fax_number')]
        [String]$FaxNumber = '',

        [String]$Website = '',

        [Alias('id_number')]
        [String]$IdNumber = '',

        [Alias('parent_company_id')]
        [Int]$ParentCompanyId,

        [String]$Notes = '',

        [string]$Slug
    )

    $Object = Get-HuduCompanies -Id $Id

    $Company = [ordered]@{company = $Object }

    if ($Name) {
        $Company.company.name = $Name
    }

    if ($Nickname) {
        $Company.company.nickname = $Nickname
    }

    if ($CompanyType) {
        $Company.company.company_type = $CompanyType
    }

    if ($AddressLine1) {
        $Company.company.address_line_1 = $AddressLine1
    }

    if ($AddressLine2) {
        $Company.company.address_line_2 = $AddressLine2
    }

    if ($City) {
        $Company.company.city = $City
    }
    
    if ($State) {
        $Company.company.state = $State
    }

    if ($Zip) {
        $Company.company.zip = $Zip
    }

    if ($CountryName) {
        $Company.company.country_name = $CountryName
    }

    if ($PhoneNumber) {
        $Company.company.phone_number = $PhoneNumber
    }

    if ($FaxNumber) {
        $Company.company.fax_number = $FaxNumber
    }

    if ($Website) {
        $Company.company.website = $Website
    }

    if ($IdNumber) {
        $Company.company.id_number = $IdNumber
    }

    if ($ParentCompanyId) {
        $Company.company.parent_company_id = $ParentCompanyId
    }

    if ($Notes) {
        $Company.company.notes = $Notes
    }

    if ($Slug) {
        $Company.company.slug = $Slug
    }

    $JSON = $Company | ConvertTo-Json -Depth 10

    if ($PSCmdlet.ShouldProcess($Id)) {
        Invoke-HuduRequest -Method put -Resource "/api/v1/companies/$Id" -Body $JSON
    }
}
#EndRegion '.\Public\Set-HuduCompany.ps1' 185
#Region '.\Public\Set-HuduCompanyArchive.ps1' -1

function Set-HuduCompanyArchive {
    <#
    .SYNOPSIS
    Archive/Unarchive a company

    .DESCRIPTION
    Uses Hudu API to set archive status on a company

    .PARAMETER Id
    Id of the requested company

    .PARAMETER Archive
    Boolean for archive status

    .EXAMPLE
    Set-HuduCompanyArchive -Id 1 -Archive $true

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [Int]$Id,
        [Parameter(Mandatory = $true)]
        [Bool]$Archive
    )

    if ($Archive -eq $true) {
        $Action = 'archive'
    } else {
        $Action = 'unarchive'
    }
    if ($PSCmdlet.ShouldProcess($Id)) {
        Invoke-HuduRequest -Method put -Resource "/api/v1/companies/$Id/$Action"
    }
}
#EndRegion '.\Public\Set-HuduCompanyArchive.ps1' 36
#Region '.\Public\Set-HuduFlag.ps1' -1

function Set-HuduFlag {
    <#
    .SYNOPSIS
    Update a flag

    .DESCRIPTION
    Uses Hudu API to update a Flag. If updating the flagable association,
    flagable_type must be valid and the record must exist.

    .PARAMETER Id
    ID of the flag to update

    .PARAMETER FlagTypeId
    Updated flag type ID

    .PARAMETER Description
    Updated description

    .PARAMETER flagable_type
    Updated flagable type (Asset, Website, Article, AssetPassword, Company, Procedure, RackStorage, Network, IpAddress, Vlan, VlanZone)

    .PARAMETER flagable_id
    Updated flagable record ID

    .EXAMPLE
    Set-HuduFlag -Id 10 -Description "Updated flag description" -FlagTypeId 2

    .EXAMPLE
    Set-HuduFlag -Id 10 -flagable_type Asset -flagable_id 123
    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param(
        [Parameter(Mandatory = $true)]
        [Alias('FlagId','flag_id')]
        [int]$Id,

        [Alias('flag_type_id',"flagType_Id")]
        [int]$FlagTypeId,

        [string]$Description = '',

        [Alias('flaggabletype','flaggable_type','flagabletype','Flag_type','FlagType')]
        [ValidateScript({Assert-AllowedObjectType -InputType $_ -AllowedCanonicals @(
                "Vlan", "Procedure", "Website", "RackStorage", "Network", "IpAddress", "Article", "Company", "AssetPassword", "Asset","VlanZone"
        )})]
        [string]$Flagable_Type,

        [Alias("FlaggableId","flaggable_id","flagableid")]
        [int]$flagable_id
    )

    $Object = Get-HuduFlags -Id $Id
    if (-not $Object) { return $null }

    $Flag = [ordered]@{ flag = $Object }

    if ($PSBoundParameters.ContainsKey('FlagTypeId')) {
        $Flag.flag.flag_type_id = $FlagTypeId
    }

    if ($Description) {
        $Flag.flag.description = $Description
    }

    if ($flagable_type) {
        $Flag.flag.flagable_type = $(Get-ObjectTypeFromCononical -inputData $flagable_type)
    }

    if ($PSBoundParameters.ContainsKey('flagable_id')) {
        $Flag.flag.flagable_id = $flagable_id
    }

    $JSON = $Flag | ConvertTo-Json -Depth 10

    if ($PSCmdlet.ShouldProcess($Id)) {
        Invoke-HuduRequest -Method PUT -Resource "/api/v1/flags/$Id" -Body $JSON
    }
}
#EndRegion '.\Public\Set-HuduFlag.ps1' 79
#Region '.\Public\Set-HuduFlagType.ps1' -1

function Set-HuduFlagType {
    <#
    .SYNOPSIS
    Update a flag type

    .DESCRIPTION
    Uses Hudu API to update a Flag Type

    .PARAMETER Id
    ID of the flag type to update

    .PARAMETER Name
    Updated name

    .PARAMETER Color
    Human friendly color name. Valid colors are: Red, Blue, Green, Yellow, Purple, Orange, LightPink, LightBlue, LightGreen, LightPurple, LightOrange, LightYellow, White, Grey

    .EXAMPLE
    Set-HuduFlagType -Id 1 -Name "Updated Flag Type" -Color "Green"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param(
        [Parameter(Mandatory = $true)]
        [int]$Id,

        [string]$Name = '',

        [Parameter()]
        [ValidateSet('red', 'crimson', 'scarlet', 'rot', 'karminrot', 'scharlachrot', 'rouge', 'cramoisi', 'écarlate', 'rosso', 'cremisi', 'scarlatto', 'rojo', 'carmesí', 'escarlata', 'blue', 'navy', 'blau', 'marineblau', 'bleu', 'bleu marine', 'blu', 'blu navy', 'azul', 'azul marino', 'green', 'lime', 'grün', 'limettengrün', 'vert', 'vert citron', 'verde', 'verde lime', 'verde lima', 'yellow', 'gold', 'gelb', 'jaune', 'or', 'giallo', 'oro', 'amarillo', 'purple', 'violet', 'lila', 'violett', 'pourpre', 'viola', 'porpora', 'púrpura', 'violeta', 'orange', 'arancione', 'naranja', 'light pink', 'pink', 'baby pink', 'hellrosa', 'rosa', 'rose clair', 'rose', 'rosa chiaro', 'rosa claro', 'light blue', 'baby blue', 'sky blue', 'hellblau', 'babyblau', 'himmelblau', 'bleu clair', 'bleu ciel', 'azzurro', 'blu chiaro', 'azul claro', 'celeste', 'light green', 'mint', 'hellgrün', 'mintgrün', 'vert clair', 'menthe', 'verde chiaro', 'menta', 'verde claro', 'light purple', 'lavender', 'helllila', 'lavendel', 'violet clair', 'lavande', 'viola chiaro', 'lavanda', 'morado claro', 'light orange', 'peach', 'hellorange', 'pfirsich', 'orange clair', 'pêche', 'arancione chiaro', 'pesca', 'naranja claro', 'melocotón', 'light yellow', 'cream', 'hellgelb', 'creme', 'jaune clair', 'crème', 'giallo chiaro', 'crema', 'amarillo claro', 'white', 'weiß', 'blanc', 'bianco', 'blanco', 'grey', 'gray', 'silver', 'grau', 'silber', 'gris', 'argent', 'grigio', 'argento', 'plateado', 'lightpink', 'lightblue', 'lightgreen', 'lightpurple', 'lightorange', 'lightyellow',IgnoreCase = $true)]
        [string]$Color
    )

    $Object = Get-HuduFlagTypes -Id $Id
    if (-not $Object) { return $null }

    $FlagType = [ordered]@{ flag_type = $Object }
    if ($Name)  { $FlagType.flag_type.name  = $Name }
    if ($Color) { $FlagType.flag_type.color = $(Set-ColorFromCanonical -inputData $Color) }

    $JSON = $FlagType | ConvertTo-Json -Depth 10

    if ($PSCmdlet.ShouldProcess($Id)) {
        $result = Invoke-HuduRequest -Method PUT -Resource "/api/v1/flag_types/$Id" -Body $JSON
        return ($result.flag_type ?? $result)
    }
}
#EndRegion '.\Public\Set-HuduFlagType.ps1' 47
#Region '.\Public\Set-HuduFolder.ps1' -1

function Set-HuduFolder {
    <#
    .SYNOPSIS
    Update a Folder

    .DESCRIPTION
    Uses Hudu API to update a folder

    .PARAMETER Id
    Id of the requested folder

    .PARAMETER Name
    Name of the folder

    .PARAMETER Icon
    Folder icon

    .PARAMETER Description
    Folder description

    .PARAMETER ParentFolderId
    Folder parent id

    .PARAMETER CompanyId
    Folder company id

    .EXAMPLE
    Set-HuduFolder -Id 1 -Name 'New folder name'

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [Int]$Id,

        [String]$Name,

        [String]$Icon,

        [String]$Description,

        [Alias('parent_folder_id')]
        [Nullable[int]]$ParentFolderId,

        [Alias('company_id')]
        [Nullable[int]]$CompanyId
    )

    $folderObject = get-hudufolders -id $id; $folderobject = $folderobject.folder ?? $folderobject;

    $Folder = [ordered]@{folder = [ordered]@{} }

    if ($PSBoundParameters.ContainsKey('Name')) {
        $Folder.folder.add('name', $Name)
    } else {
        $Folder.folder.add('name', $folderObject.name)
    }

    if ($PSBoundParameters.ContainsKey('Icon')) {
        $Folder.folder.add('icon', $Icon)
    } else {
        $Folder.folder.add('icon', $folderObject.icon)
    }

    if ($PSBoundParameters.ContainsKey('Description')) {
        $Folder.folder.add('description', $Description)
    } else {
        $Folder.folder.add('description', $folderObject.description)
    }

    if ($PSBoundParameters.ContainsKey('ParentFolderId')) {
        $Folder.folder.add('parent_folder_id', $ParentFolderId)
    } else {
        $Folder.folder.add('parent_folder_id', $folderObject.parent_folder_id)
    }

    if ($PSBoundParameters.ContainsKey('CompanyId')) {
        $Folder.folder.add('company_id', $CompanyId)
    } else {
        $Folder.folder.add('company_id', $folderObject.company_id)
    }

    $JSON = $Folder | ConvertTo-Json

    if ($PSCmdlet.ShouldProcess($Id)) {
        Invoke-HuduRequest -Method put -Resource "/api/v1/folders/$Id" -Body $JSON
    }
}
#EndRegion '.\Public\Set-HuduFolder.ps1' 89
#Region '.\Public\Set-HuduIntegrationMatcher.ps1' -1

function Set-HuduIntegrationMatcher {
    <#
    .SYNOPSIS
    Update a Matcher

    .DESCRIPTION
    Uses Hudu API to set integration matchers

    .PARAMETER Id
    Id of the requested matcher

    .PARAMETER AcceptSuggestedMatch
    Set the Sync Id/Identifier to the suggested one

    .PARAMETER CompanyId
    Requested company id to match

    .PARAMETER PotentialCompanyId
    Potential company id to match

    .PARAMETER SyncId
    Sync id to match

    .PARAMETER Identifier
    Identifier to match

    .EXAMPLE
    Set-HuduIntegrationMatcher -Id 1 -AcceptSuggestedMatch

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [String]$Id,

        [Parameter(ParameterSetName = 'AcceptSuggestedMatch')]
        [switch]$AcceptSuggestedMatch,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'SetCompanyId')]
        [Alias('company_id')]
        [String]$CompanyId,

        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [Alias('potential_company_id')]
        [String]$PotentialCompanyId,

        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [Alias('sync_id')]
        [String]$SyncId,

        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [String]$Identifier
    )

    process {
        $Matcher = [ordered]@{matcher = [ordered]@{} }

        if ($AcceptSuggestedMatch) {
            $Matcher.matcher.add('company_id', $PotentialCompanyId) | Out-Null
        } else {
            $Matcher.matcher.add('company_id', $CompanyId) | Out-Null
        }

        if ($PotentialCompanyId) {
            $Matcher.matcher.add('potential_company_id', $PotentialCompanyId) | Out-Null
        }
        if ($SyncId) {
            $Matcher.matcher.add('sync_id', $SyncId) | Out-Null
        }
        if ($Identifier) {
            $Matcher.matcher.add('identifier', $identifier) | Out-Null
        }

        $JSON = $Matcher | ConvertTo-Json -Depth 10

        if ($PSCmdlet.ShouldProcess($Id)) {
            Invoke-HuduRequest -Method put -Resource "/api/v1/matchers/$Id" -Body $JSON
        }
    }
}
#EndRegion '.\Public\Set-HuduIntegrationMatcher.ps1' 81
#Region '.\Public\Set-HuduIPAddress.ps1' -1

function Set-HuduIPAddress {
<#
.SYNOPSIS
Update a Hudu IP address.

.DESCRIPTION
Updates fields on an existing Hudu IPAM IP address record.
Returns the updated object on success, the existing object if nothing changed, or $null on failure.

.PARAMETER Id
The unique IP record ID to update (required).

.PARAMETER Address
New IP address string (e.g. '192.168.10.25').

.PARAMETER Status
New IP status string as used by Hudu (e.g. 'active', 'reserved', 'available').
Value is lowercased before request.

.PARAMETER FQDN
New FQDN for this IP.

.PARAMETER Description
New description text.

.PARAMETER Notes
New notes text.

.PARAMETER AssetId
Asset ID to (re)link this IP to.

.PARAMETER NetworkId
Parent Network ID to (re)associate with.

.PARAMETER CompanyId
Company ID to (re)associate with.

.PARAMETER SkipDNSValidation
If specified, controls whether the server should skip DNS validation ('true'/'false' sent).
If $true, the server should skip DNS validation for FQDN (default: $true). [note- DNS validation only works if your hudu instance can resolve dns to this address, so public or same-private network]

.OUTPUTS
pscustomobject (updated IP object), the existing object (if no changes), or $null on failure.

.EXAMPLE
Set-HuduIPAddress -Id 1234 -Status active -Notes 'Now assigned to core switch'

.EXAMPLE
# Update multiple fields, preserving existing unset ones
Set-HuduIPAddress -Id 1234 -IncludeExisting -FQDN 'cam01.example.com' -Description 'Parking lot camera'

.EXAMPLE
# Toggle DNS validation behavior
Set-HuduIPAddress -Id 1234 -SkipDNSValidation:$false

.NOTES
If no updatable parameters are provided, the cmdlet returns the existing object and exits.
'SkipDNSValidation' is serialized as a lowercased string value per API expectations.

#>


    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Id,
        [string]$Address,
        [string]$Status,
        [string]$FQDN,
        [string]$Description,
        [string]$Notes,
        [int]$AssetID,
        [int]$NetworkId,
        [int]$CompanyID,
        [bool]$SkipDNSValidation=$true
    )
        try {
            $existing = Get-HuduIPAddresses -Id $Id
        } catch {
            Write-Verbose "Unable to fetch existing IP address $Id- $_"
            return
        }

        $attrs = @{}

        if ($IncludeExisting.IsPresent -and $existing) {
            foreach ($prop in @('address','status','fqdn','description','notes','asset_id','network_id','company_id','skip_dns_validation')) {
                if ($existing.PSObject.Properties.Match($prop)) {
                    $value = $existing.$prop
                    if ($null -ne $value) { $attrs[$prop] = $value }
                }
            }
        }

        if ($PSBoundParameters.ContainsKey('Address'))        { $attrs.address             = $Address }
        if ($PSBoundParameters.ContainsKey('FQDN'))           { $attrs.fqdn                = $FQDN }
        if ($PSBoundParameters.ContainsKey('Description'))    { $attrs.description         = $Description }
        if ($PSBoundParameters.ContainsKey('Notes'))          { $attrs.notes               = $Notes }
        if ($PSBoundParameters.ContainsKey('AssetId'))        { $attrs.asset_id            = $AssetId }
        if ($PSBoundParameters.ContainsKey('NetworkId'))      { $attrs.network_id          = $NetworkId }
        if ($PSBoundParameters.ContainsKey('CompanyId'))      { $attrs.company_id          = $CompanyId }
        if ($PSBoundParameters.ContainsKey('Status'))         { $attrs.status              = "$Status".ToLower() }
        if ($PSBoundParameters.ContainsKey('SkipDNSValidation')) {
            $attrs.skip_dns_validation = "$SkipDNSValidation".ToLower()
        }

        if ($attrs.Count -eq 0) {
            Write-Verbose "No properties provided to update for IP $Id. Exiting."
            return $existing
        }

        $payload = @{ ip_address = $attrs } | ConvertTo-Json -Depth 10

        try {
            $response = Invoke-HuduRequest -Method PUT -Resource "/api/v1/ip_addresses/$Id" -Body $payload
            return $response
        } catch {
            Write-Warning "Failed to update IP address $Id- $_"
            return $null
        }

}
#EndRegion '.\Public\Set-HuduIPAddress.ps1' 123
#Region '.\Public\Set-HuduLabel.ps1' -1

function Set-HuduLabel {
<#
.SYNOPSIS
Updates a Label.

.DESCRIPTION
Updates a Label by ID. The same applicability and uniqueness rules as creation apply.

.PARAMETER Id
ID of the Label to update.

.PARAMETER LabelTypeId
Updated Label Type ID.

.PARAMETER Labelable_Type
Updated target record type.

.PARAMETER Labelable_Id
Updated target record ID.

.EXAMPLE
Set-HuduLabel -Id 10 -Labelable_Type Asset -Labelable_Id 456

.EXAMPLE
Set-HuduLabel -Id 10 -LabelTypeId 2

.NOTES
API Endpoint: PUT /api/v1/labels/{id}
#>

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [Alias('LabelId','label_id')]
        [int]$Id,

        [Alias('label_type_id','labeltype_id','label_typeid','label_type','type_id','typeid')]
        [int]$LabelTypeId,

        [ValidateScript({ Assert-AllowedObjectType -InputType $_ -AllowedCanonicals @(
            'Article', 'Asset', 'AssetPassword', 'Website', 'IpAddress', 'Vlan', 'VlanZone', 'Procedure', 'Network', 'RackStorage'
        ) })]
        [Alias('object_type','objectType','target_type','targetType')]
        [string]$Labelable_Type,

        [Alias('object_id','objectID','target_id','targetId')]
        [int]$Labelable_Id
    )

    $object = Get-HuduLabels -Id $Id
    if (-not $object) { return $null }

    if ($PSBoundParameters.ContainsKey('LabelTypeId')) {
        $object | Add-Member -MemberType NoteProperty -Name label_type_id -Force -Value $LabelTypeId
    }
    if ($PSBoundParameters.ContainsKey('Labelable_Type')) {
        $object | Add-Member -MemberType NoteProperty -Name labelable_type -Force -Value (Get-ObjectTypeFromCononical -inputData $Labelable_Type)
    }
    if ($PSBoundParameters.ContainsKey('Labelable_Id')) {
        $object | Add-Member -MemberType NoteProperty -Name labelable_id -Force -Value $Labelable_Id
    }

    $body = @{ label = $object } | ConvertTo-Json -Depth 99

    if ($PSCmdlet.ShouldProcess("Label Id=$Id", "Update")) {
        $resp = Invoke-HuduRequest -Method PUT -Resource "/api/v1/labels/$Id" -Body $body
        return ($resp.label ?? $resp)
    }
}
#EndRegion '.\Public\Set-HuduLabel.ps1' 70
#Region '.\Public\Set-HuduLabelType.ps1' -1

function Set-HuduLabelType {
<#
.SYNOPSIS
Updates a Label Type.

.DESCRIPTION
Updates a Label Type by ID. When setting AccessLevel to specific_companies,
AllowedCompanyIds must contain at least one company ID, either from the existing
Label Type or from the provided parameter.

.PARAMETER Id
ID of the Label Type to update.

.PARAMETER Name
Updated name.

.PARAMETER Color
Updated hex color value for the Label Type, such as #1c12a3, or a
human-readable color name supported by Set-ColorFromCanonical. Alpha values are
trimmed off.

.PARAMETER AccessLevel
Updated access scope.

.PARAMETER ApplicableRecordTypes
Updated list of record types this Label Type can be applied to.

.PARAMETER AllowedCompanyIds
Updated list of company IDs allowed to use this Label Type when AccessLevel is specific_companies.

.EXAMPLE
Set-HuduLabelType -Id 1 -Name "AnotherLabel" -Color "scharlachrot"

.EXAMPLE
Set-HuduLabelType -Id 1 -Name "Critical" -Color "#ff0000"

.EXAMPLE
Set-HuduLabelType -Id 1 -Name "Colorful" -Color "naranja" -ApplicableRecordTypes @("asset","motdepasse","internetseite","procédure","netzwerk")

.NOTES
API Endpoint: PUT /api/v1/label_types/{id}
#>

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [Alias('LabelTypeId','label_type_id','labeltype_id','label_typeid','type_id','typeid')]
        [int]$Id,

        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [ValidateNotNullOrEmpty()]
        [string]$Color,

        [ValidateSet('all_companies', 'all', 'allcompanies', 'allcompany', 'specific_companies', 'specific', 'specificcompanies', 'specificcompany', IgnoreCase = $true)]
        [Alias('access_level')]
        [string]$AccessLevel,

        [ValidateNotNullOrEmpty()]
        [ValidateScript({
            foreach ($recordType in $_) {
                Assert-AllowedObjectType -InputType $recordType -AllowedCanonicals @(
                    'Article', 'Asset', 'AssetPassword', 'Website', 'IpAddress', 'Vlan', 'VlanZone', 'Procedure', 'Network', 'RackStorage'
                ) | Out-Null
            }
            $true
        })]
        [Alias('applicable_record_types','record_types','types','applicableTypes','applicable_type','applicableType')]
        [string[]]$ApplicableRecordTypes,

        [Alias('allowed_company_ids','companyids','company_ids','companyId','company_id','companies')]
        [int[]]$AllowedCompanyIds
    )
    $AccessLevelMap = @{
        'all_companies'             = 'all_companies'
        'all'                       = 'all_companies'
        'allcompanies'              = 'all_companies'
        'allcompany'                = 'all_companies'
        'specific_companies'        = 'specific_companies'
        'specific'                  = 'specific_companies'
        'specificcompanies'         = 'specific_companies'
        'specificcompany'           = 'specific_companies'
    }

    $object = Get-HuduLabelTypes -Id $Id
    if (-not $object) { return $null }

    if ($PSBoundParameters.ContainsKey('Name')) {
        $object | Add-Member -MemberType NoteProperty -Name name -Force -Value $Name
    }
    if ($PSBoundParameters.ContainsKey('Color')) {
        $object | Add-Member -MemberType NoteProperty -Name color -Force -Value (ConvertTo-HuduLabelColor -Color $Color)
    }
    if ($PSBoundParameters.ContainsKey('AccessLevel')) {
        $normalizedAccessLevel = $AccessLevelMap[$AccessLevel.ToLower()]
        if (-not $normalizedAccessLevel) {
            throw "Invalid AccessLevel value '$AccessLevel'. Valid values are: $($AccessLevelMap.Keys -join ', ')."
        }
        $object | Add-Member -MemberType NoteProperty -Name access_level -Force -Value $normalizedAccessLevel
    }
    if ($PSBoundParameters.ContainsKey('ApplicableRecordTypes')) {
        $recordTypes = @($ApplicableRecordTypes | ForEach-Object { Get-ObjectTypeFromCononical -inputData $_ })
        $object | Add-Member -MemberType NoteProperty -Name applicable_record_types -Force -Value $recordTypes
    }
    if ($PSBoundParameters.ContainsKey('AllowedCompanyIds')) {
        $object | Add-Member -MemberType NoteProperty -Name allowed_company_ids -Force -Value @($AllowedCompanyIds)
    }

    $effectiveAccessLevel = $object.access_level
    $effectiveAllowedCompanyIds = @($object.allowed_company_ids)
    if ($effectiveAccessLevel -eq 'specific_companies' -and -not $effectiveAllowedCompanyIds) {
        throw "AllowedCompanyIds must contain at least one company ID when AccessLevel is specific_companies."
    }

    $body = @{ label_type = $object } | ConvertTo-Json -Depth 99

    if ($PSCmdlet.ShouldProcess("Label Type Id=$Id", "Update")) {
        $resp = Invoke-HuduRequest -Method PUT -Resource "/api/v1/label_types/$Id" -Body $body
        return ($resp.label_type ?? $resp)
    }
}
#EndRegion '.\Public\Set-HuduLabelType.ps1' 123
#Region '.\Public\Set-HuduList.ps1' -1

function Set-HuduList {
    <#
    .SYNOPSIS
    Update an existing Hudu List

    .DESCRIPTION
    Calls the Hudu API to update a List. You may modify item names, add new items, or mark items for deletion.

    .PARAMETER Id
    ID of the list to update

    .PARAMETER Name
    New name for the list

    .PARAMETER ListItems
    Array of item hashtables. Use `id` and `name` to update, or `_destroy = $true` to remove.

    .EXAMPLE
    Update-HuduList -Id 456 -Name "Updated List" -ListItems @(
        @{ id = 1; name = "Updated Value" },
        @{ name = "New Value" },
        @{ id = 2; _destroy = $true }
    )
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Id,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [hashtable[]]$ListItems
    )

    $payload = @{
        list = @{
            name = $Name
            list_items_attributes = $ListItems
        }
    } | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-HuduRequest -Method PUT -Resource "/api/v1/lists/$Id" -Body $payload
        return $response
    } catch {
        Write-Warning "Failed to update list with ID $Id"
        return $null
    }
}
#EndRegion '.\Public\Set-HuduList.ps1' 52
#Region '.\Public\Set-HuduMagicDash.ps1' -1

function Set-HuduMagicDash {
    <#
    .SYNOPSIS
    Create or Update a Magic Dash Item

    .DESCRIPTION
    Magic Dash takes just simple key-pairs. Whether you want to add a new Magic Dash Item, or update one, you can use the same endpoint, so it is really easy! It uses the title, and company_name to match.

    .PARAMETER Title
    This is the title. If there is an existing Magic Dash Item with matching title and company_name, then it will match into that item.

    .PARAMETER CompanyName
    This is the attribute we use to match to an existing company. If there is an existing Magic Dash Item with matching title and company_name, then it will match into that item.

    .PARAMETER Message
    This will be the first content that will be displayed on the Magic Dash Item.

    .PARAMETER Icon
    Either fill this in, or image_url. Use a (FontAwesome icon for the header of a Magic Dash Item. Must be in the format of fas fa-circle

    .PARAMETER ImageURL
    Either fill this in, or icon. Used in the header of a Magic Dash Item.

    .PARAMETER ContentLink
    Either fill this in, or content, or leave both blank. Used to have a link to an external website.

    .PARAMETER Content
    Either fill this in, or content_link, or leave both blank. Fill in with HTML (tables, images, videos, etc.) to display more content in your Magic Dash Item.

    .PARAMETER Shade
    Use a different color for your Magic Dash Item for different contextual states. Options are to leave it blank, success, or danger

    .EXAMPLE
    Set-HuduMagicDash -Title 'Test Dash' -CompanyName 'Test Company' -Message 'This will be displayed first'

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [String]$Title,

        [Alias('company_name')]
        [Parameter(Mandatory = $true)]
        [String]$CompanyName,

        [Parameter(Mandatory = $true)]
        [String]$Message,

        [String]$Icon = '',

        [Alias('image_url')]
        [String]$ImageURL = '',

        [Alias('content_link')]
        [String]$ContentLink = '',

        [String]$Content = '',

        [String]$Shade = ''
    )

    if ($Icon -and $ImageURL) {
        Write-Error ('You can only use one of icon or image URL')
        exit 1
    }

    if ($content_link -and $content) {
        Write-Error ('You can only use one of content or content_link')
        exit 1
    }

    $MagicDash = [ordered]@{}

    if ($Title) {
        $MagicDash.add('title', $Title)
    }

    if ($CompanyName) {
        $MagicDash.add('company_name', $CompanyName)
    }

    if ($Message) {
        $MagicDash.add('message', $Message)
    }

    if ($Icon) {
        $MagicDash.add('icon', $Icon)
    }

    if ($ImageURL) {
        $MagicDash.add('image_url', $ImageURL)
    }

    if ($ContentLink) {
        $MagicDash.add('content_link', $ContentLink)
    }

    if ($Content) {
        $MagicDash.add('content', $Content)
    }

    if ($Shade) {
        $MagicDash.add('shade', $Shade)
    }

    $JSON = $MagicDash | ConvertTo-Json

    if ($PSCmdlet.ShouldProcess("$Companyname - $Title")) {
        Invoke-HuduRequest -Method post -Resource '/api/v1/magic_dash' -Body $JSON
    }
}
#EndRegion '.\Public\Set-HuduMagicDash.ps1' 112
#Region '.\Public\Set-HuduNetwork.ps1' -1

function Set-HuduNetwork {
<#
.SYNOPSIS
Update a Hudu network.

.DESCRIPTION
Updates a Hudu IPAM Network object for a Company.
Returns the updated network object on success, or $null on failure.

.PARAMETER Id
The unique network ID to update. (Required)

.PARAMETER Name
New name for the network.

.PARAMETER Address
CIDR notation for the network (e.g. 192.168.10.0/24).

.PARAMETER CompanyId
Company ID to associate with the network.

.PARAMETER LocationId
Location ID to associate with the network.

.PARAMETER Description
Free-form description of the network.

.PARAMETER NetworkType
Numeric network type as used by Hudu (module/API enum value).

.PARAMETER VlanId
VLAN identifier for the network.

.EXAMPLE
Set-HuduNetwork -Id 123 -Name "Core LAN" -Description "Primary office network"

.EXAMPLE
Set-HuduNetwork -Id 123 -Address "10.20.30.0/24" -VlanId 30 -LocationId 456
#>    

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Id,
        [string]$Name,
        [string]$Address,
        [int]$CompanyId,
        [nullable[int]]$LocationId,
        [string]$Description,
        [int]$NetworkType,
        [nullable[int]]$VlanId
    )
    $object = Get-HuduNetworks -id $Id
    $hudunetwork = [ordered]@{network = $object }

    if ($Name) {
        $hudunetwork.network | Add-Member -MemberType NoteProperty -Name name -Force -Value $Name
    }
    if ($Address) {
        $hudunetwork.network | Add-Member -MemberType NoteProperty -Name address -Force -Value $Address
    }
    if ($CompanyId) {
        $hudunetwork.network | Add-Member -MemberType NoteProperty -Name company_id -Force -Value $CompanyId
    }
    if ($Description) {
        $hudunetwork.network | Add-Member -MemberType NoteProperty -Name description -Force -Value $Description
    }
    if ($NetworkType) {
        $hudunetwork.network | Add-Member -MemberType NoteProperty -Name network_type -Force -Value $NetworkType
    }
    if ($PSBoundParameters.ContainsKey('LocationId')) {
        $hudunetwork.network | Add-Member -MemberType NoteProperty -Name location_id -Force -Value $LocationId
    }
    if ($PSBoundParameters.ContainsKey('VlanId')) {
        $hudunetwork.network | Add-Member -MemberType NoteProperty -Name vlan_id -Force -Value $VlanId
    }
 


    $payload = $hudunetwork | ConvertTo-Json -depth 10
    try {
        $response = Invoke-HuduRequest -Method PUT -Resource "/api/v1/networks/$Id" -Body $payload
        return $response
    } catch {
        Write-Warning "Failed to set network '$Id'"
        return $null
    }
}
#EndRegion '.\Public\Set-HuduNetwork.ps1' 89
#Region '.\Public\Set-HuduPassword.ps1' -1

function Set-HuduPassword {
    <#
    .SYNOPSIS
    Update a Password

    .DESCRIPTION
    Uses Hudu API to update a password

    .PARAMETER Id
    Id of the requested Password

    .PARAMETER Name
    Password name

    .PARAMETER CompanyId
    Id of requested company

    .PARAMETER PasswordableType
    associated Object type, most commonly asset, for the password ["Asset"]

    .PARAMETER PasswordableId
    Associated object id for the password

    .PARAMETER InPortal
    Display password in portal

    .PARAMETER Password
    Password

    .PARAMETER OTPSecret
    OTP secret

    .PARAMETER URL
    Url for the password

    .PARAMETER Username
    Username

    .PARAMETER Description
    Password description

    .PARAMETER PasswordType
    Password type

    .PARAMETER PasswordFolderId
    Id of requested password folder

    .PARAMETER Slug
    Url identifier

    .EXAMPLE
    Set-HuduPassword -Id 1 -CompanyId 1 -Password 'this_is_my_new_password'

    #>
    [CmdletBinding(SupportsShouldProcess)]
    # This will silence the warning for variables with Password in their name.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingUsernameAndPasswordParams', '')]
    Param (
        [Parameter(Mandatory = $true)]
        [Int]$Id,

        [String]$Name,

        [Alias('company_id')]
        [Int]$CompanyId,

        [Alias('passwordable_type')]
        [ValidateScript({Assert-AllowedObjectType -InputType $_ -AllowedCanonicals @(
                "Asset"
        )})]         
        [String]$PasswordableType,

        [Alias('passwordable_id')]
        [int]$PasswordableId,

        [Alias('in_portal')]
        [Bool]$InPortal = $false,
        [String]$Password,

        [Alias('otp_secret')]
        [string]$OTPSecret,

        [String]$URL,

        [String]$Username,

        [String]$Description,

        [Alias('password_type')]
        [String]$PasswordType,

        [Alias('password_folder_id')]
        [int]$PasswordFolderId,

        [string]$Slug
    )

    $Object = Get-HuduPasswords -Id $Id 
    $AssetPassword = [ordered]@{asset_password = $Object }

    if ($PSBoundParameters.ContainsKey('Name'))   { 
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name name -Force -Value $Name   
    }
    if ($PSBoundParameters.ContainsKey('CompanyId'))   { 
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name company_id -Force -Value $CompanyId
    }
    if ($PSBoundParameters.ContainsKey('Password'))   { 
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name password -Force -Value $Password
    }
    if ($PSBoundParameters.ContainsKey('InPortal'))   { 
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name in_portal -Force -Value $InPortal
    }
    if ($PSBoundParameters.ContainsKey('OTPSecret'))   { 
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name otp_secret -Force -Value $OTPSecret
    }
    if ($PSBoundParameters.ContainsKey('URL'))   { 
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name url -Force -Value $URL
    }
    if ($PSBoundParameters.ContainsKey('Username'))   { 
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name username -Force -Value $Username
    }
    if ($PSBoundParameters.ContainsKey('Description'))   { 
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name description -Force -Value $Description
    }
    if ($PSBoundParameters.ContainsKey('PasswordType'))   { 
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name password_type -Force -Value $PasswordType
    }
    if ($PSBoundParameters.ContainsKey('PasswordableType')) {
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name passwordable_type -Force -Value $(Get-ObjectTypeFromCononical -inputData $PasswordableType)
    }
    if ($PSBoundParameters.ContainsKey('PasswordFolderId') -and ($PasswordFolderId -gt 0 -or $null -eq $PasswordFolderId)) {
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name password_folder_id -Force -Value $PasswordFolderId
    }    
    if ($PSBoundParameters.ContainsKey('PasswordableId') -and ($PasswordableId -gt 0 -or $null -eq $PasswordableId)) {
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name passwordable_id -Force -Value $PasswordableId
    }
    if ($Slug) {
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name slug -Force -Value $Slug
    }
    $JSON = $AssetPassword | ConvertTo-Json -Depth 10

    if ($PSCmdlet.ShouldProcess($Id)) {
        Invoke-HuduRequest -Method put -Resource "/api/v1/asset_passwords/$Id" -Body $JSON
    }
}
#EndRegion '.\Public\Set-HuduPassword.ps1' 147
#Region '.\Public\Set-HuduPasswordArchive.ps1' -1

function Set-HuduPasswordArchive {
    <#
    .SYNOPSIS
    Archive/Unarchive a Password

    .DESCRIPTION
    Uses Hudu API to archive or unarchive a password

    .PARAMETER Id
    Id of the requested Password

    .PARAMETER Archive
    Boolean of archive status

    .EXAMPLE
    Set-HuduPasswordArchive -Archive $true -Id 1

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [Int]$Id,
        [Parameter(Mandatory = $true)]
        [Bool]$Archive
    )

    process {
        if ($Archive) {
            $Action = 'archive'
        } else {
            $Action = 'unarchive'
        }

        if ($PSCmdlet.ShouldProcess($Id)) {
            Invoke-HuduRequest -Method put -Resource "/api/v1/asset_passwords/$Id/$Action"
        }
    }
}
#EndRegion '.\Public\Set-HuduPasswordArchive.ps1' 39
#Region '.\Public\Set-HuduPasswordFolder.ps1' -1

function Set-HuduPasswordFolder {
    <#
    .SYNOPSIS
    Update an existing password folder.

    .DESCRIPTION
    Calls the Hudu API to update details of an existing password folder.  
    You can change the name, description, security mode, or allowed groups.

    .PARAMETER Id
    The numeric ID of the folder to update (required).

    .PARAMETER Name
    New folder name. If omitted, the existing name is retained.

    .PARAMETER Description
    New description. If omitted, the existing description is retained.

    .PARAMETER Security
    Security mode. Accepts "all_users" or "specific".

    .PARAMETER AllowedGroups
    Array of group IDs that should have access (if Security is "specific").

    .EXAMPLE
    Set-HuduPasswordFolder -Id 5 -Name "Updated Folder"
    Renames folder ID 5 to "Updated Folder".

    .EXAMPLE
    Set-HuduPasswordFolder -Id 7 -Security specific -AllowedGroups @(3,4)
    Restricts folder ID 7 access to groups 3 and 4.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][int]$Id,
        [string]$Name,
        [string]$Description,
        [ValidateSet("all_users","specific")][String]$Security,
        [array]$AllowedGroups,
        [Alias('company_id')]
        [nullable[int]]$CompanyID
    )
    
    $passwordFolder = Get-HuduPasswordFolders -Id $Id 
    
    $updatePasswordFolder=@{
        name        = $(if ($Name) {$Name} else {$passwordFolder.name})
        description = $(if ($Description) {$Description} else {$passwordFolder.description})
    }
    if ($passwordFolder.company_id){
        $updatePasswordFolder.company_id = $passwordFolder.company_id
    }

    if ($PSBoundParameters.ContainsKey('CompanyID'))   { $passwordFolder.company_id   = $CompanyID }
    
    if (($AllowedGroups -and $AllowedGroups -ne $passwordFolder.allowed_groups) -or ($security -and $security -eq "specific")){
        $updatePasswordFolder["security"] = $security
        $allGroups = $(Get-HuduGroups).id
        if ($($AllowedGroups | where-object {$allGroups -contains $_}).count -gt 1) {
            $updatePasswordFolder["allowed_groups"]= $AllowedGroups | where-object {$allGroups -contains $_}
        } elseif ($passwordFolder.allowed_groups) {
            $updatePasswordFolder["allowed_groups"]= $passwordFolder.allowed_groups
        } else {
            $updatePasswordFolder["allowed_groups"]= @("0")
        }
    } else {
        $updatePasswordFolder["security"] = $passwordFolder.security
        $updatePasswordFolder["allowed_groups"] = $passwordFolder.allowed_groups
    }
    if ($updatePasswordFolder["security"] -eq "all_users"){
        $updatePasswordFolder["allowed_groups"] = @()
    }


    try {
        $res = Invoke-HuduRequest -Method PUT -Resource "/api/v1/password_folders/$ID" -Body $(@{password_folder = $passwordFolder} | ConvertTo-Json -Depth 10)
        return $res
    } catch {
        Write-Warning "Failed to create new password folder '$Name'"
        return $null
    }
}
#EndRegion '.\Public\Set-HuduPasswordFolder.ps1' 83
#Region '.\Public\Set-HuduPhoto.ps1' -1

function Set-HuduPhoto {
    param(
        [Parameter(Mandatory)]
        [int]$Id,


        [int]$CompanyId,
        [Alias('uploadabletype','recordtype','PhotoableType','uploadable_type','record_type')]
        [ValidateScript({Assert-AllowedObjectType -InputType $_ -AllowedCanonicals @(
                "Website", "RackStorage", "IpAddress", "Article", "Company", "Asset", "AssetPassword"
        )})]
        [string]$Photoable_Type,
        
        [Alias('record_id','uploadable_id','recordid','PhotoableId','uploadableid')]
        [int]$Photoable_Id,

        [Alias('folder_id')]
        [int]$FolderId,

        [Nullable[bool]]$Archived,
        [Nullable[bool]]$Pinned,
        [string]$Caption
    )
    [version]$script:Version = $script:Version ?? [version]((Get-HuduAppInfo).version)
    if ($script:Version -lt [version]'2.41.0') {
        write-warning "Set-HuduPhoto: Hudu version $($script:Version) is below 2.41.0; Skipping."
        return $null
    }
    $params = @{}
    # proper casing for hudu API 

    if ($PSBoundParameters.ContainsKey('CompanyId')) { $params.company_id = $CompanyId }
    if ($PSBoundParameters.ContainsKey('Caption'))   { $params.caption = $Caption }
    if ($PSBoundParameters.ContainsKey('Pinned'))      { $params.pinned = "$([bool]$Pinned)".ToString().ToLower() }
    if ($PSBoundParameters.ContainsKey('FolderId'))  { $params.folder_id = $(if ($null -eq $FolderId -or $folderID -lt 1){"null"} else {"$FolderId"} )}
    if ($PSBoundParameters.ContainsKey('archived'))  { $params.archived = "$([bool]$Archived)".ToString().ToLower() }

    if ($PSBoundParameters.ContainsKey('Photoable_Type') -and $PSBoundParameters.ContainsKey('Photoable_Id')) { 
        $params.photoable_type  = $(Get-ObjectTypeFromCononical -inputData $Photoable_Type)
        $params.photoable_id    = $Photoable_Id
    } elseif ($PSBoundParameters.ContainsKey('CompanyId')) { 
        $params.photoable_type = "Company"
        $params.photoable_id =$CompanyId
    }
    
    $result = invoke-hudurequest -Method PUT -Resource "/api/v1/photos/$Id" -Body $(@{photo = $params} | ConvertTo-Json -Depth 99)

    return $result.photo ?? $result
}
#EndRegion '.\Public\Set-HuduPhoto.ps1' 50
#Region '.\Public\Set-HuduProcedure.ps1' -1

function Set-HuduProcedure {
    <#
    .SYNOPSIS
    Update an existing Hudu process or run.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Id,

        [string]$Name,
        [string]$Description,
        [Nullable[int]]$CompanyId,
        [Nullable[bool]]$Archived
    )

    $procedure = @{}

    if ($PSBoundParameters.ContainsKey('Name'))        { $procedure.name = $Name }
    if ($PSBoundParameters.ContainsKey('Description')) { $procedure.description = $Description }
    if ($PSBoundParameters.ContainsKey('CompanyId'))   { $procedure.company_id = $CompanyId }
    if ($PSBoundParameters.ContainsKey('Archived'))    { $procedure.archived = $Archived }

    if ($procedure.Count -eq 0) {
        throw "No fields were supplied to update."
    }

    $payload = $procedure | ConvertTo-Json -Depth 10

    try {
        $res = Invoke-HuduRequest -Method PUT -Resource "/api/v1/procedures/$Id" -Body $payload
        return ($res.procedure ?? $res)
    }
    catch {
        Write-Warning "Failed to update procedure ID $Id- $($_.Exception.Message)"
        return $null
    }
}
#EndRegion '.\Public\Set-HuduProcedure.ps1' 39
#Region '.\Public\Set-HuduProcedureTask.ps1' -1

function Set-HuduProcedureTask {
<#
.SYNOPSIS
Update a procedure task.

.DESCRIPTION
Updates an existing procedure task associated with either a procedure template
or a procedure run.

Behavior differs depending on Hudu version:

- Pre-2.41.0:
  Tasks are updated using legacy behavior. All provided fields are accepted.

- 2.41.0 and later:
  Tasks may belong to either a procedure template or a run.

Run-only fields:
  The following parameters only apply to tasks associated with runs:
    - Priority
    - UserId
    - AssignedUsers
    - DueDate

Forgiving behavior:
  - If run-only fields are provided for a non-run task, they are ignored and a warning is emitted.
  - The command will still update all compatible fields.
  - Unlike creation, updates will not automatically create or switch to a run context.

Notes:
  - Changing ProcedureId will update the task's associated procedure if supported by the API.
  - -RunTask indicates intent but does not force run behavior.

.PARAMETER Id
ID of the procedure task to update.

.PARAMETER Name
New task name.

.PARAMETER Description
New task description.

.PARAMETER Completed
Mark the task as completed or not.

.PARAMETER ProcedureId
Reassign the task to a different procedure or run.

.PARAMETER Position
Update task ordering position.

.PARAMETER UserId
Run-only. Single user assignment.

.PARAMETER AssignedUsers
Run-only. Array of user IDs.

.PARAMETER DueDate
Run-only. Due date.

.PARAMETER Priority
Run-only. Task priority.

.PARAMETER RunTask
Indicates intent to operate on a run task. If the target is not a run,
run-only fields will be ignored.

.PARAMETER AutoKickoff
(Not typically used for updates.) Included for compatibility; does not
automatically convert a template task into a run task.

#>    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [int]$Id,
        [string]$Name,
        [string]$Description,
        [bool]$Completed,
        [int]$ProcedureId,
        [int]$Position,
        [int]$UserId,
        [string]$DueDate,
        [ValidateSet("unsure", "low", "normal", "high", "urgent")]
        [string]$Priority,
        [int[]]$AssignedUsers,

        # 2.41.0+ only
        [switch]$RunTask,
        [switch]$AutoKickoff
    )

    if (-not $script:HuduVersion) {
        [version]$script:HuduVersion = (Get-HuduAppInfo).version
    }

    if ($script:HuduVersion -lt [version]'2.41.0') {
        if ($PSBoundParameters.ContainsKey('RunTask') -or $PSBoundParameters.ContainsKey('AutoKickoff')) {
            Write-Verbose "RunTask/AutoKickoff are not used on Hudu versions earlier than 2.41.0."
        }

        $legacyParams = @{}
        foreach ($kv in $PSBoundParameters.GetEnumerator()) {
            $legacyParams[$kv.Key] = $kv.Value
        }

        [void]$legacyParams.Remove('RunTask')

        return Set-HuduProcedureTaskLegacy @legacyParams
    }

    return Set-HuduProcedureTaskV241 @PSBoundParameters
}
#EndRegion '.\Public\Set-HuduProcedureTask.ps1' 113
#Region '.\Public\Set-HuduProcedureTaskLegacy.ps1' -1

function Set-HuduProcedureTaskLegacy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [int]$Id,
        [string]$Name,
        [string]$Description,
        [bool]$Completed,
        [int]$ProcedureId,
        [int]$Position,
        [int]$UserId,
        [string]$DueDate,
        [ValidateSet("unsure", "low", "normal", "high", "urgent")]
        [string]$Priority,
        [int[]]$AssignedUsers,
        [switch]$RunTask, # ignored in legacy method
        [switch]$AutoKickoff # ignored in legacy method        
    )

    $task = @{}
    if ($PSBoundParameters.ContainsKey('Name'))          { $task.name = $Name }
    if ($PSBoundParameters.ContainsKey('Description'))   { $task.description = $Description }
    if ($PSBoundParameters.ContainsKey('Completed'))     { $task.completed = $Completed }
    if ($PSBoundParameters.ContainsKey('ProcedureId'))   { $task.procedure_id = $ProcedureId }
    if ($PSBoundParameters.ContainsKey('Position'))      { $task.position = $Position }
    if ($PSBoundParameters.ContainsKey('UserId'))        { $task.user_id = $UserId }
    if ($PSBoundParameters.ContainsKey('DueDate'))       { $task.due_date = $DueDate }
    if ($PSBoundParameters.ContainsKey('Priority'))      { $task.priority = $Priority }
    if ($PSBoundParameters.ContainsKey('AssignedUsers')) { $task.assigned_users = $AssignedUsers }

    $payload = @{ procedure_task = $task } | ConvertTo-Json -Depth 10

    try {
        $res = Invoke-HuduRequest -Method PUT -Resource "/api/v1/procedure_tasks/$Id" -Body $payload
        return ($res.procedure_task ?? $res)
    }
    catch {
        Write-Warning "Failed to update procedure task ID $Id : $($_.Exception.Message)"
        return $null
    }
}
#EndRegion '.\Public\Set-HuduProcedureTaskLegacy.ps1' 41
#Region '.\Public\Set-HuduProcedureTaskV241.ps1' -1

function Set-HuduProcedureTaskV241 {
<#
.SYNOPSIS
Update a procedure task (Hudu 2.41.0+ behavior).

.DESCRIPTION
Updates a task belonging to either a procedure template or a run.

Run-only fields (Priority, UserId, AssignedUsers, DueDate) are:
  - Applied only when the task belongs to a run
  - Ignored with a warning when applied to a template task

This implementation favors compatibility and will update all valid fields
while ignoring incompatible ones.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$Id,

        [string]$Name,

        [string]$Description,

        [bool]$Completed,

        [int]$ProcedureId,

        [int]$Position,

        [int]$UserId,

        [datetime]$DueDate,

        [ValidateSet("unsure", "low", "normal", "high", "urgent")]
        [string]$Priority,

        [int[]]$AssignedUsers,

        [switch]$RunTask
    )

    $existingTask = Get-HuduProcedureTasks -Id $Id
    if (-not $existingTask) {
        throw "Could not retrieve procedure task ID $Id."
    }

    $targetProcedureId = if ($PSBoundParameters.ContainsKey('ProcedureId')) {
        $ProcedureId
    }
    else {
        $existingTask.procedure_id
    }

    if (-not $targetProcedureId) {
        throw "Could not determine procedure ID for task ID $Id."
    }

    $procedureContext = Get-HuduProcedureContext -ProcedureId $targetProcedureId
    if (-not $procedureContext) {
        throw "Could not determine procedure context for procedure ID $targetProcedureId."
    }

    $runOnlyFields = @('Priority','UserId','AssignedUsers','DueDate')
    $presentRunFields = @($runOnlyFields.Where({ $PSBoundParameters.ContainsKey($_) }))
    $runParamsPresent = $presentRunFields.Count -gt 0

    $isRun = ($procedureContext.IsRun -eq $true)

    if ($RunTask -and -not $isRun) {
        Write-Warning "Task ID $Id is not associated with a run. Run-only fields will be ignored."
    }

    $task = @{}

    if ($PSBoundParameters.ContainsKey('Name'))         { $task.name         = $Name }
    if ($PSBoundParameters.ContainsKey('Description'))  { $task.description  = $Description }
    if ($PSBoundParameters.ContainsKey('Completed'))    { $task.completed    = $Completed }
    if ($PSBoundParameters.ContainsKey('ProcedureId'))  { $task.procedure_id = $targetProcedureId }
    if ($PSBoundParameters.ContainsKey('Position'))     { $task.position     = $Position }

    if ($isRun) {
        if ($PSBoundParameters.ContainsKey('Priority'))      { $task.priority       = $Priority }
        if ($PSBoundParameters.ContainsKey('UserId'))        { $task.user_id        = $UserId }
        if ($PSBoundParameters.ContainsKey('AssignedUsers')) { $task.assigned_users = $AssignedUsers }
        if ($PSBoundParameters.ContainsKey('DueDate'))       { $task.due_date       = $DueDate.ToString('yyyy-MM-dd') }
    } elseif ($runParamsPresent) {
        [void]$task.Remove('priority')
        [void]$task.Remove('user_id')
        [void]$task.Remove('assigned_users')
        [void]$task.Remove('due_date')

        Write-Warning ("The following fields can only be set on run tasks and were ignored for procedure/template task update: {0}" -f ($presentRunFields -join ', '))
    }

    $payload = @{ procedure_task = $task } | ConvertTo-Json -Depth 10

    try {
        $res = Invoke-HuduRequest -Method PUT -Resource "/api/v1/procedure_tasks/$Id" -Body $payload
        return ($res.procedure_task ?? $res)
    }
    catch {
        Write-Warning "Failed to update procedure task ID $Id- $($_.Exception.Message)"
        return $null
    }
}
#EndRegion '.\Public\Set-HuduProcedureTaskV241.ps1' 107
#Region '.\Public\Set-HuduPublicPhoto.ps1' -1

function Set-HuduPublicPhoto {
    <#
    .SYNOPSIS
    Update the associated record type and ID for a specific public photo.

    .DESCRIPTION
    Reassociate a public photo object. Backward Compatibility: This endpoint still accepts numeric IDs in the path parameter for existing integrations, but responses will include the new slug-based ID format.

    .PARAMETER Id
    The id of the public photo to update

    .PARAMETER RecordId
    Record id to associate with the photo

    .PARAMETER RecordType
    Record type to associate with the photo

    .EXAMPLE
    Set-HuduPublicPhoto -id 123 -RecordId 1 -RecordType 'asset'
    Set-HuduPublicPhoto -id 432 -RecordId 7 -RecordType 'article'

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [Alias('photo_id')]
        [object]$id,

        [Parameter(Mandatory)]
        [Alias('record_id')]
        [int]$RecordId,

        [Parameter(Mandatory)]
        [Alias('record_type')]
        [ValidateScript({Assert-AllowedObjectType -InputType $_ -AllowedCanonicals @(
                "Asset", "Article"
        )})]
        [string]$RecordType
        
    )
    $photo = get-hudupublicphotos | Where-Object { $_.numeric_id -eq $id -or $_.id -eq $id } | Select-Object -first 1
    $photo = $photo.public_photo ?? $photo
    if (-not $photo) {throw "File not found!"}
    if (-not $RecordId) {throw "RecordId is required!"}
    if (-not $RecordType) {throw "RecordType is required!"}
    
    if ($photo.record_id -eq $RecordId -and $photo.record_type -eq $RecordType) {
        Write-Verbose "Photo already associated with Record ID $RecordId and Record Type $RecordType. No changes made."
        return
    }
    if ($PSCmdlet.ShouldProcess($File.FullName)) {
        Invoke-HuduRequest -Method PUT -Resource "/api/v1/public_photos/$($photo.numeric_id)" `
            -Form @{
                'record_id'   = $RecordId
                'record_type' = $RecordType
            }
    }
}
#EndRegion '.\Public\Set-HuduPublicPhoto.ps1' 59
#Region '.\Public\Set-HuduRackStorage.ps1' -1

function Set-HuduRackStorage {
    <#
    .SYNOPSIS
    Update an existing Rack Storage in Hudu.

    .DESCRIPTION
    Calls the Hudu API to update a Rack Storage by ID. You can update any subset of properties including name, dimensions, company, or location.

    .PARAMETER Id
    ID of the Rack Storage to update.

    .PARAMETER Name
    Updated name for the Rack Storage.

    .PARAMETER LocationId
    Updated location ID for the Rack Storage.

    .PARAMETER CompanyId
    Updated company ID associated with the Rack Storage.

    .PARAMETER Description
    Optional updated description for the Rack Storage.

    .PARAMETER MaxWattage
    Maximum power rating (watts) for the updated Rack Storage.

    .PARAMETER StartingUnit
    The new starting rack unit number.

    .PARAMETER Height
    The new height in rack units (U).

    .PARAMETER Width
    The new width of the rack.

    .EXAMPLE
    Set-HuduRackStorage -Id 123 -Name "Rack A-02" -Height 45

    Updates Rack Storage 123 to be renamed "Rack A-02" with 45U height.

    .NOTES
    API Endpoint: PUT /api/v1/rack_storages/{id}
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][int]$Id,

        [string]$Name,

        [int]$CompanyId,

        [int]$Height,

        [int]$Width,

        [int]$LocationId,

        [string]$Description,

        [int]$MaxWattage,

        [int]$StartingUnit

    )

    $Body = @{}
    if ($Name)          { $Body.name = $Name }
    if ($LocationId)    { $Body.location_id = $LocationId }
    if ($CompanyId)     { $Body.company_id = $CompanyId }
    if ($Description)   { $Body.description = $Description }
    if ($MaxWattage)    { $Body.max_wattage = $MaxWattage }
    if ($StartingUnit)  { $Body.starting_unit = $StartingUnit }
    if ($Height)        { $Body.height = $Height }
    if ($Width)         { $Body.width = $Width }

    $Request = @{
        Method   = 'PUT'
        Resource = "/api/v1/rack_storages/$Id"
        Body     = ($Body | ConvertTo-Json -Depth 10)
    }

    Invoke-HuduRequest @Request
}
#EndRegion '.\Public\Set-HuduRackStorage.ps1' 85
#Region '.\Public\Set-HuduRackStorageItem.ps1' -1

function Set-HuduRackStorageItem {
    <#
    .SYNOPSIS
    Update an existing Rack Storage Item in Hudu.

    .DESCRIPTION
    Calls the Hudu API to update a Rack Storage Item using its ID. You can modify any of the properties such as associated asset, rack units, power draw, and reserved message.

    .PARAMETER Id
    The ID of the Rack Storage Item to update.

    .PARAMETER RackStorageRoleId
    The ID of the Rack Storage Role to associate with this item.

    .PARAMETER AssetId
    The ID of the Asset to associate with this rack slot.

    .PARAMETER StartUnit
    The rack unit where this asset begins (e.g., 1 for top of rack).

    .PARAMETER EndUnit
    The rack unit where this asset ends.

    .PARAMETER Status
    A status code indicating the usage or reservation state of the rack item.

    .PARAMETER Side
    The side of the rack the item is on ('Front' or 'Rear').

    .PARAMETER MaxWattage
    The maximum power capacity allowed for this item.

    .PARAMETER PowerDraw
    The actual power draw of the asset, in watts.

    .PARAMETER ReservedMessage
    A text message displayed when the item is reserved.

    .EXAMPLE
    Set-HuduRackStorageItem -Id 456 -StartUnit 10 -EndUnit 15 -Side "Rear" -PowerDraw 120

    Updates the Rack Storage Item 456 to span units 10–15 on the rear side and sets its power draw to 120W.

    .NOTES
    API Endpoint: PUT /api/v1/rack_storage_items/{id}
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [int]$Id,

        [int]$RackStorageRoleId,

        [int]$AssetId,

        [int]$StartUnit,

        [int]$EndUnit,

        [int]$Status,

        [ValidateSet(1, 0)][int]$Side,

        [int]$MaxWattage,

        [int]$PowerDraw,

        [string]$ReservedMessage
    )

    $Body = @{}

    if ($RackStorageRoleId) { $Body.rack_storage_role_id = $RackStorageRoleId }
    if ($AssetId)           { $Body.asset_id = $AssetId }
    if ($EndUnit)           { $Body.end_unit = $EndUnit }
    if ($MaxWattage)        { $Body.max_wattage = $MaxWattage }
    if ($PowerDraw)         { $Body.power_draw = $PowerDraw }
    if ($ReservedMessage)   { $Body.reserved_message = $ReservedMessage }

    $existing = Get-HuduRackStorageItems -Id $Id

    if (-not $PSBoundParameters.ContainsKey('StartUnit')) {
        $StartUnit = $existing.start_unit
    }
    if (-not $PSBoundParameters.ContainsKey('Side')) {
        $Side = if ($existing.side.ToLower() -eq "front") {0} else {1}
    }
    if (-not $PSBoundParameters.ContainsKey('Status')) {
        $Status = if ($existing.status.toLower() -eq "reserved") {0} else {1}
    }

    $HuduRequest = @{
        Method      = 'PUT'
        Resource    = "/api/v1/rack_storage_items/$Id"
        Body        = ($Body | ConvertTo-Json -Depth 10)
    }
    Invoke-HuduRequest @HuduRequest
}
#EndRegion '.\Public\Set-HuduRackStorageItem.ps1' 100
#Region '.\Public\Set-HuduRequestOption.ps1' -1

function Set-HuduRequestOption {
    <#
    .SYNOPSIS
    Set options for how requests to the Hudu API are made

    .DESCRIPTION
    A failed request (other than a rate-limited one) is retried once after -RetryDelaySeconds. A POST that failed after
    Hudu had already created the record (for example a timeout) then creates it a second time; -SkipPostRetry turns the
    retry off for POST requests only.

    A rate-limited request waits until the next rate limit window starts (plus a few seconds of jitter), then is retried.
    Windows are -RateLimitWindowSeconds long, counted from midnight.

    Only the options passed are changed. The current options are returned.

    .PARAMETER SkipPostRetry
    Do not retry a failed POST request. Default: $false

    .PARAMETER RetryDelaySeconds
    Seconds to wait before retrying a failed request. Default: 5

    .PARAMETER RateLimitWindowSeconds
    Length of the rate limit window, in seconds. Default: 300

    .EXAMPLE
    Set-HuduRequestOption -SkipPostRetry $true

    .EXAMPLE
    Set-HuduRequestOption -RetryDelaySeconds 2 -RateLimitWindowSeconds 60

    .NOTES
    The options last for the session, like the API key and base URL
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Scope = 'Function')]
    [CmdletBinding()]
    Param (
        [bool]$SkipPostRetry,

        [ValidateRange(0, 3600)]
        [int]$RetryDelaySeconds,

        [ValidateRange(1, 3600)]
        [int]$RateLimitWindowSeconds
    )

    if ($PSBoundParameters.ContainsKey('SkipPostRetry')) { $script:SKIP_HAPI_POST_RETRY = $SkipPostRetry }
    if ($PSBoundParameters.ContainsKey('RetryDelaySeconds')) { $script:HAPI_RETRY_DELAY_SECONDS = $RetryDelaySeconds }
    if ($PSBoundParameters.ContainsKey('RateLimitWindowSeconds')) { $script:HAPI_RATE_LIMIT_WINDOW_SECONDS = $RateLimitWindowSeconds }

    [pscustomobject]@{
        SkipPostRetry          = [bool]$script:SKIP_HAPI_POST_RETRY
        RetryDelaySeconds      = $script:HAPI_RETRY_DELAY_SECONDS ?? 5
        RateLimitWindowSeconds = $script:HAPI_RATE_LIMIT_WINDOW_SECONDS ?? 300
    }
}
#EndRegion '.\Public\Set-HuduRequestOption.ps1' 56
#Region '.\Public\Set-HuduVLAN.ps1' -1

function Set-HuduVLAN {
<#
.SYNOPSIS
Update an existing VLAN.

.DESCRIPTION
Modifies VLAN properties such as name, company association, description, role/status list Ids, 
VLAN Id, VLAN Zone association, or archival status.

.PARAMETER Id
The Id of the VLAN to update.

.PARAMETER Name
New VLAN name.

.PARAMETER CompanyId
Company identifier (optional override).

.PARAMETER Description
Update the description text.

.PARAMETER RoleListItemID
Update the role list item association.

.PARAMETER StatusListItemID
Update the status list item association.

.PARAMETER VLANId
Update the VLAN Id (between 4 and 4094).

.PARAMETER VLANZoneId
Associate with a VLAN Zone.

.PARAMETER Archived
Set archival status: "true" or "false".

.EXAMPLE
Set-HuduVLAN -Id 7 -Description "Changed purpose" -VLANId 250
#>    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [int]$Id,
        [string]$Name,
        [int]$CompanyId,
        [string]$Description,
        [int]$RoleListItemID,
        [int]$StatusListItemID,
        [ValidateRange(4,4094)][int]$VLANId,
        [int]$VLANZoneId,
        [ValidateSet("true","false")][string]$Archived
    )
    $vlan = Get-HuduVLANs -id $Id
    if ($Name) {
        $vlan | Add-Member -MemberType NoteProperty -Name name -Force -Value $Name
    }
    if ($CompanyId) {
        $vlan | Add-Member -MemberType NoteProperty -Name company_id -Force -Value $CompanyId
    }
    if ($Description) {
        $vlan | Add-Member -MemberType NoteProperty -Name description -Force -Value $Description
    }
    if ($RoleListItemID) {
        $vlan | Add-Member -MemberType NoteProperty -Name role_list_item_id -Force -Value $RoleListItemID
    }
    if ($StatusListItemID) {
        $vlan | Add-Member -MemberType NoteProperty -Name status_list_item_id -Force -Value $StatusListItemID
    }            
    if ($VLANId) {
        $vlan | Add-Member -MemberType NoteProperty -Name vlan_id -Force -Value $VLANId
    }
    if ($VLANZoneId) {
        $vlan | Add-Member -MemberType NoteProperty -Name vlan_zone_id -Force -Value $VLANZoneId
    }
    if ($Archived) {
        $vlan | Add-Member -MemberType NoteProperty -Name archived -Force -Value $Archived
    }

    $payload = @{
        vlan             = $vlan
    } | ConvertTo-Json -Depth 10

    try {
        $res = Invoke-HuduRequest -Method PUT -Resource "/api/v1/vlans/$Id" -Body $payload
        return $res
    } catch {
        Write-Warning "Failed to vlan ID $Id"
        return $null
    }
}
#EndRegion '.\Public\Set-HuduVLAN.ps1' 90
#Region '.\Public\Set-HuduVLANZone.ps1' -1

function Set-HuduVLANZone {
<#
.SYNOPSIS
Update an existing VLAN Zone.

.DESCRIPTION
Modifies VLAN Zone properties such as company, description, VLAN Id ranges, or archival status.

.PARAMETER Id
The Id of the VLAN Zone to update.

.PARAMETER CompanyId
Company identifier (optional override).

.PARAMETER Description
Update the description text.

.PARAMETER VLANIdRanges
New VLAN ranges string (e.g. "100-200,300-350").

.PARAMETER Archived
Set archival status: "true" or "false".

.EXAMPLE
Set-HuduVLANZone -Id 5 -Description "Updated description" -Archived "false"

#>`    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)] [int]$Id,
        [int]$CompanyId,
        [string]$Description,
        # VLAN ranges: "1-4", "200-300,400-450", etc.
        [ValidatePattern('^([1-9][0-9]{0,3}-[1-9][0-9]{0,3})(,([1-9][0-9]{0,3}-[1-9][0-9]{0,3}))*$')]
        [string]$VLANIdRanges,
        [ValidateSet("true","false")][string]$Archived
    )
    $vlan_zone = Get-HuduVLANZones -id $Id
    if ($Archived) {
        $vlan_zone | Add-Member -MemberType NoteProperty -Name archived -Force -Value $Archived
    }
    if ($VLANIdRanges) {
        $vlan_zone | Add-Member -MemberType NoteProperty -Name vlan_id_ranges -Force -Value $VLANIdRanges
    }
    if ($Description) {
        $vlan_zone | Add-Member -MemberType NoteProperty -Name description -Force -Value $Description
    }
    if ($CompanyId) {
        $vlan_zone | Add-Member -MemberType NoteProperty -Name company_id -Force -Value $CompanyId
    }
        


    $payload = @{
        vlan_zone = $vlan_zone
    } | ConvertTo-Json -Depth 10

    try {
        $res = Invoke-HuduRequest -Method PUT -Resource "/api/v1/vlan_zones/$Id" -Body $payload
        return $res
    } catch {
        Write-Warning "Failed to archive vlan zone ID $Id"
        return $null
    }
}
#EndRegion '.\Public\Set-HuduVLANZone.ps1' 66
#Region '.\Public\Set-HuduWebsite.ps1' -1

function Set-HuduWebsite {
    <#
    .SYNOPSIS
    Update a Website

    .DESCRIPTION
    Uses Hudu API to update a website

    .PARAMETER Id
    Id of requested website

    .PARAMETER Name
    Website name (e.g. https://example.com)

    .PARAMETER Notes
    Website Notes

    .PARAMETER Paused
    When true, website monitoring is paused.

    .PARAMETER CompanyId
    Used to associate website with company

    .PARAMETER DisableDNS
    When true, dns monitoring is paused.

    .PARAMETER DisableSSL
    When true, ssl cert monitoring is paused.

    .PARAMETER DisableWhois
    When true, whois monitoring is paused.

    .PARAMETER EnableDMARC
    When true, DMARC monitoring is enabled.
    
    .PARAMETER EnableDKIM
    When true, DKIM monitoring is enabled.
    
    .PARAMETER EnableSPF
    When true, SPF monitoring is enabled.

    .PARAMETER Slug
    Url identifier

    .EXAMPLE
    Set-HuduWebsite -Id 1 -Paused $true

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [Int]$Id,

        [Parameter()]
        [String]$Name,

        [String]$Notes = '',

        [String]$Paused = '',

        [Alias('company_id')]
        [Parameter()]
        [Int]$CompanyId,

        [Alias('disable_dns')]
        [String]$DisableDNS = '',

        [Alias('disable_ssl')]
        [String]$DisableSSL = '',

        [Alias('disable_whois')]
        [String]$DisableWhois = '',

        [Alias('enable_dmarc')]
        [String]$EnableDMARC = '',

        [Alias('enable_dkim')]
        [String]$EnableDKIM = '',

        [Alias('enable_spf')]
        [String]$EnableSPF = '',

        [string]$Slug
    )
    
    $Object = Get-HuduWebsites -Id $Id
    if (-not $Object) {
        Throw "Website with Id $Id not found or invalid object returned."
    }
    $Website = [ordered]@{website = $Object }

    If ($Name) {
        $Website.website.name = $Name
    }

    if ($Notes) {
        $Website.website.notes = $Notes
    }

    if ($Paused) {
        $Website.website.paused = $Paused
    }

    if ($CompanyId) {
        $Website.website.company_id = $companyid
    }

    if ($DisableDNS) {
        $Website.website.disable_dns = $DisableDNS
    }

    if ($DisableSSL) {
        $Website.website.disable_ssl = $DisableSSL
    }

    if ($DisableWhois) {
        $Website.website.disable_whois = $DisableWhois
    }

    if ($Slug) {
        $Website.website.slug = $Slug
    }

    if ($EnableDMARC) {
        $Website.website.enable_dmarc_tracking = $EnableDMARC
    }

    if ($EnableDKIM) {
        $Website.website.enable_dkim_tracking = $EnableDKIM
    }

    if ($EnableSPF) {
        $Website.website.enable_spf_tracking = $EnableSPF
    }

    $JSON = $Website | ConvertTo-Json -Depth 10

    if ($PSCmdlet.ShouldProcess($Id)) {
        Invoke-HuduRequest -Method put -Resource "/api/v1/websites/$Id" -Body $JSON
    }
}
#EndRegion '.\Public\Set-HuduWebsite.ps1' 142
#Region '.\Public\Set-HuduWebsiteArchive.ps1' -1

function Set-HuduWebsiteArchive {
    <#
    .SYNOPSIS
    Update a Website to be archived or unarchived

    .DESCRIPTION
    Uses Hudu API to archive or unarchive a website

    .PARAMETER Archive
    Boolean of archive status

        .EXAMPLE
    Set-HuduWebsiteArchive -Archive $true -Id 1

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [Int]$Id,

        [Parameter(Mandatory = $true)]
        [Alias('Archived')]
        [bool]$Archive
    )
    process {
    
        $Object = Get-HuduWebsites -Id $Id
        if (-not $Object) {
            Throw "Website with Id $Id not found or invalid object returned."
        }


        $Website = [ordered]@{website = $Object }
        $Website.website.archived = $Archive
        
        if ($PSCmdlet.ShouldProcess($Id)) {
            $JSON = $Website | ConvertTo-Json -Depth 10
            Invoke-HuduRequest -Method put -Resource "/api/v1/websites/$Id" -Body $JSON
        }
    }
}
#EndRegion '.\Public\Set-HuduWebsiteArchive.ps1' 42
#Region '.\Public\Start-HuduExport.ps1' -1

function Start-HuduExport {
    <#
    .SYNOPSIS
    Initiate a PDF or CSV backup of Hudu Data for a given company

    .DESCRIPTION
    Uses Hudu API to initiate a backup for a company

    .PARAMETER CompanyId
    Company Identifier for company you wish to initiate export for

    .PARAMETER AssetLayoutIDs
    Optional- List/Array for Layout Identifiers you'd like to include in backup, defaults to all

    .PARAMETER IncludePasswords
    Include Passwords in export, true/false (defaults to false if not provided)

    .PARAMETER IncludeWebsites
    Include Websites in export, true/false (defaults to true if not provided)

    .PARAMETER format
    format desired for export (csv or pdf)
    #>    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [int]$CompanyId,
        [array]$AssetLayoutIDs=$null,
        [bool]$IncludePasswords=$false,
        [bool]$IncludeWebsites=$true,
        [ValidateSet("pdf","csv","PDF","CSV")][string]$format='pdf'
    )
    if ($null -eq $AssetLayoutIDs -or $AssetLayoutIDs.count -lt 1){
        $AssetLayoutIDs =  $(get-huduAssetLayouts).id
    }
    $payload = @{
        export = @{
            include_websites        = "$($IncludeWebsites)".ToLower()
            include_passwords       = "$($IncludePasswords)".ToLower()
            company_id              = $CompanyId
            format                  = "$($format)".ToLower()
            asset_layout_ids        = @($AssetLayoutIDs)
        }} | ConvertTo-Json -Depth 10
    try {
        $res = Invoke-HuduRequest -Method POST -Resource "/api/v1/exports" -Body $payload
        return $res
    } catch {
        Write-Warning "Failed to initiate backup for company $CompanyID- $_"
    }
}
#EndRegion '.\Public\Start-HuduExport.ps1' 51
#Region '.\Public\Start-HuduProcedure.ps1' -1

function Start-HuduProcedure {
    <#
    .SYNOPSIS
    Start a run from an existing company procedure.

    .DESCRIPTION
    Creates a new run by calling POST /api/v1/procedures/{id}/kickoff.

    Only company procedures can be kicked off.
    Global templates must first be copied to a company procedure.
    If the target is already a run, kickoff is not performed.

    .PARAMETER ProcedureId
    ID of the procedure to kick off.

    .PARAMETER AssetId
    Optional asset ID to associate with the new run.

    .PARAMETER Name
    Optional name for the new run.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Alias('Id')]
        [int]$ProcedureId,

        [int]$AssetId,

        [string]$Name
    )

    $procedureContext = Get-HuduProcedureContext -ProcedureId $ProcedureId
    if (-not $procedureContext) {
        throw "Could not determine procedure context for procedure ID $ProcedureId."
    }

    if ($procedureContext.IsRun) {
        Write-Warning "Procedure ID $ProcedureId is already a run. Kick off is not applicable."
        return $null
    }


    if ($procedureContext.CanKickoff -ne $true) {
        Write-Warning "Procedure ID $ProcedureId cannot be kicked off. Ensure it is a company procedure and not already a run."
        return $null
    }

    if (
        $procedureContext.IsGlobal -or
        $procedureContext.ProcessType -eq 'global' -or
        [string]::IsNullOrWhiteSpace([string]$procedureContext.CompanyId)
    ) {
        Write-Warning "Procedure ID $ProcedureId is a global template. It must be copied to a company procedure before it can be kicked off."
        return $null
    }    

    $params = @{}
    if ($PSBoundParameters.ContainsKey('AssetId')) { $params.asset_id = $AssetId }
    if ($PSBoundParameters.ContainsKey('Name'))    { $params.name = $Name }

    try {
        
        $r = Invoke-HuduRequest -Method POST -Resource "/api/v1/procedures/$ProcedureId/kickoff" -Params $params
        return ($r.procedure ?? $r)
    }
    catch {
        Write-Warning "Failed to kick off procedure ID $ProcedureId- $($_.Exception.Message)"
        return $null
    }
}
#EndRegion '.\Public\Start-HuduProcedure.ps1' 72
#Region '.\Public\Start-HuduS3Export.ps1' -1

function Start-HuduS3Export {
    <#
    .SYNOPSIS
    Initiate an S3 Backup of Hudu Data (credentials must be configured in settings)

    .DESCRIPTION
    Kicks off a backup in S3 if you have configured Hudu to do this (if so, backs up every Sunday)
    #>    
    try {
        Invoke-HuduRequest -Method POST -Resource "/api/v1/s3_exports"
    } catch {
        Write-Warning "Failed to initiate S3 Export- $_"
    }
}
#EndRegion '.\Public\Start-HuduS3Export.ps1' 15

