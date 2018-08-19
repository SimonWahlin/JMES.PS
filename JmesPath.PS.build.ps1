#Requires -Modules @{ModuleName='InvokeBuild';ModuleVersion='3.2.1'}
#Requires -Modules @{ModuleName='PowerShellGet';ModuleVersion='1.6.0'}
#Requires -Modules @{ModuleName='Pester';ModuleVersion='4.1.1'}
Enter-Build {
    # This code will run in script-scope
    $IsAppveyor = $env:APPVEYOR -ne $null
    $ProjectName = Get-Item -Path $BuildRoot | Select-Object -ExpandProperty Name
    try {
        $ModuleName = Get-Item -Path "$BuildRoot\$ProjectName.psm1" -ErrorAction Stop | Select-Object -ExpandProperty BaseName
    }
    catch {
        $ModuleName = $ProjectName
    }

    $ConfigData = Import-PowerShellDataFile -Path "$BuildRoot\$ProjectName.build.psd1"
    $AssemblyPath = $Script:ConfigData.AssemblyPath
    $PrivatePath = $Script:ConfigData.PrivatePSPath
    $PublicPath = $Script:ConfigData.PublicPSPath

    Get-Module -Name $ModuleName,'helpers' | Remove-Module -Force
    Import-Module "$BuildRoot\buildhelpers\helpers.psm1"
}

task Clean {
    Remove-Item -Path ".\bin" -Recurse -Force -ErrorAction SilentlyContinue
    $null = New-Item -Path "$BuildRoot\bin\$ModuleName" -ItemType Directory
}

task MSBuild {
    foreach($BuildPath in $Script:ConfigData.BuildPaths) {
        & 'dotnet' 'publish' '-c' 'Release' '-o' "$BuildRoot\$AssemblyPath\" "$BuildRoot\$BuildPath\"
    }
    Remove-Item -Path "$BuildRoot\$AssemblyPath\system.management.automation.dll" -ErrorAction SilentlyContinue
}

task TestCode {
    Write-Build Yellow "`n`n`nTesting dev code before build"
    $TestResult = Invoke-Pester -Script "$PSScriptRoot\test\Unit" -Tag Unit -PassThru
    if($TestResult.FailedCount -gt 0) {throw 'Tests failed'}
}

task MSBuild {
    foreach($BuildPath in $Script:ConfigData.BuildPaths) {
        & 'dotnet' 'publish' '-c' 'Release' '-o' "$BuildRoot\bin\" "$BuildRoot\$BuildPath\"
        Remove-Item -Path "$BuildRoot\bin\$ModuleName\system.management.automation.dll" -ErrorAction SilentlyContinue
    }
}

task CopyFiles {
    "$BuildRoot\$ModuleName.psd1",
    "$BuildRoot\license*",
    "$BuildRoot\$AssemblyPath\*.dll" |
        Where-Object -FilterScript {Test-Path -Path $_} |
        Copy-Item -Destination "$BuildRoot\bin\$ModuleName"
}

task CompilePSM {
    $PrivatePath = '{0}\Private\*.ps1' -f $BuildRoot
    $PublicPath = '{0}\Public\*.ps1'-f $BuildRoot
    $ScriptPath = '{0}\Script\*.ps1'-f $BuildRoot
    Merge-ModuleFiles -Path $ScriptPath,$PrivatePath,$PublicPath -OutputPath "$BuildRoot\bin\$ModuleName\$ModuleName.psm1"

    $PublicScriptBlock = Get-ScriptBlockFromFile -Path $PublicPath
    $PublicFunctions = Get-FunctionFromScriptblock -ScriptBlock $PublicScriptBlock
    $PublicAlias = Get-AliasFromScriptblock -ScriptBlock $PublicScriptBlock
    $PublicFunctionParam, $PublicAliasParam = ''
    $UpdateManifestParam = @{}
    if(-Not [String]::IsNullOrEmpty($PublicFunctions)) {
        $PublicFunctionParam = "-Function '{0}'" -f ($PublicFunctions -join "','")
        $UpdateManifestParam['FunctionsToExport'] = $PublicFunctions
    }
    if($PublicAlias) {
        $PublicAliasParam = "-Alias '{0}'" -f ($PublicAlias -join "','")
        $UpdateManifestParam['AliasesToExport'] = $PublicAlias
    }
    $ExportStrings = 'Export-ModuleMember',$PublicFunctionParam,$PublicAliasParam | Where-Object {-Not [string]::IsNullOrWhiteSpace($_)}
    $ExportStrings -join ' ' | Out-File -FilePath  "$BuildRoot\bin\$ModuleName\$ModuleName.psm1" -Append -Encoding UTF8

    # If we have git and gitversion installed, let's use it to get new module version and Release Notes
    if ($(try{Get-Command -Name gitversion -ErrorAction Stop}catch{})) {
        $gitversion = gitversion | ConvertFrom-Json
        if ($gitversion.CommitsSinceVersionSource -gt 0) {
            # Prerelease, raise minor-version by 1 and add prerelease string.
            $UpdateManifestParam['ModuleVersion'] = '{0}.{1}.{2}' -f $gitversion.Major, ($gitversion.Minor+1), $gitversion.Patch
            $UpdateManifestParam['Prerelease'] = '-beta{0}' -f $gitversion.CommitsSinceVersionSourcePadded
        }
        else {
            # This is a release version
            # If there is a tag pointing at HEAD, use that as release notes
            $UpdateManifestParam['ModuleVersion'] = $gitversion.MajorMinorPatch
            if ($(try{Get-Command -Name git -ErrorAction Stop}catch{})) {
                if($CurrentTag = git tag --points-at HEAD) {
                    $ReleaseNotes = git tag -l -n20 $CurrentTag | Select-Object -Skip 1
                    $UpdateManifestParam['ReleaseNotes'] = $ReleaseNotes
                }
            }
        }
    }
    if ($UpdateManifestParam.Count -gt 0) {
        Update-ModuleManifest -Path "$BuildRoot\bin\$ModuleName\$ModuleName.psd1" @UpdateManifestParam
    }
}

task MakeHelp -if (Test-Path -Path "$PSScriptRoot\Docs") {

}

task TestBuild {
    Write-Build Yellow "`n`n`nTesting compiled module"
    $Script =  @{Path="$PSScriptRoot\test\Unit"; Parameters=@{ModulePath="$BuildRoot\bin\$ModuleName"}}
    $CodeCoverage = Get-Module "$BuildRoot\bin\$ModuleName" -ListAvailable |
        Select-Object -ExpandProperty ExportedCommands |
        Select-Object -ExpandProperty Keys | Foreach-Object -Process {
            @{Path="$BuildRoot\bin\$ModuleName\$ModuleName.psm1";Function=$_}
        }
    $TestResult = Invoke-Pester -Script $Script -Tag Unit -CodeCoverage $CodeCoverage -PassThru
    if($TestResult.FailedCount -gt 0) {throw 'Tests failed'}
}

task . Clean, TestCode, Optimize

task Optimize Build, CopyFiles, CompilePSM, MakeHelp, TestBuild
task Build MSBuild
