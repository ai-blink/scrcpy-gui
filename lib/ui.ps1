# =============================================================
#  화면 만드는 부분 — 옵션만 바꿀 거면 손댈 필요 없음 (옵션 표는 lib/config.ps1)
# =============================================================

# 이 스크립트를 띄운 검은 콘솔 창만 숨긴다 (GUI 창은 그대로 보임).
# ※ 런처에서 pwsh -WindowStyle Hidden 을 쓰면 GUI 창까지 같이 숨겨진다(실측). 그래서 여기서 처리한다.
$ConsoleWin = Add-Type -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@ -Name 'ConsoleWin' -Namespace 'Native' -PassThru
$null = $ConsoleWin::ShowWindow($ConsoleWin::GetConsoleWindow(), 0)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

[xml]$xamlDoc = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="scrcpy" Height="814" Width="1000"
        WindowStartupLocation="CenterScreen"
        Background="#1B1B1F" FontFamily="Segoe UI, 맑은 고딕" FontSize="13"
        TextOptions.TextFormattingMode="Display">

  <Window.Resources>

    <!-- 스크롤바 : 얇은 다크 -->
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="10"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid Background="Transparent">
              <Track x:Name="PART_Track" IsDirectionReversed="True">
                <Track.Thumb>
                  <Thumb>
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Border Background="#43434B" CornerRadius="5" Margin="2,0"/>
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
                <Track.IncreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0" Focusable="False"/>
                </Track.IncreaseRepeatButton>
                <Track.DecreaseRepeatButton>
                  <RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0" Focusable="False"/>
                </Track.DecreaseRepeatButton>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- 입력칸  ※ Height 고정 = 옆 설명글이 길어져도 박스가 늘어나지 않게 -->
    <Style x:Key="DarkText" TargetType="TextBox">
      <Setter Property="Height" Value="34"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="Background" Value="#26262C"/>
      <Setter Property="Foreground" Value="#E9E9EC"/>
      <Setter Property="BorderBrush" Value="#3A3A42"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,0"/>
      <Setter Property="CaretBrush" Value="#E9E9EC"/>
      <Setter Property="SelectionBrush" Value="#2C6BD6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border x:Name="Bd" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="7">
              <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="#4C4C57"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="#3D82F0"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- 명령어 미리보기 -->
    <Style x:Key="CmdBox" TargetType="TextBox" BasedOn="{StaticResource DarkText}">
      <Setter Property="Background" Value="#141418"/>
      <Setter Property="Foreground" Value="#8FD9A8"/>
      <Setter Property="FontFamily" Value="Consolas"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="IsReadOnly" Value="True"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="BorderBrush" Value="#2C2C34"/>
      <Setter Property="Height" Value="Auto"/>
      <Setter Property="VerticalAlignment" Value="Stretch"/>
      <Setter Property="VerticalContentAlignment" Value="Top"/>
      <Setter Property="Padding" Value="11,9"/>
    </Style>

    <!-- 선택목록 -->
    <Style x:Key="ComboItem" TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="#D8D8DE"/>
      <Setter Property="Padding" Value="10,7"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="Bd" Background="Transparent" Padding="{TemplateBinding Padding}" CornerRadius="4" Margin="3,1">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#33333C"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#2C4E86"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="DarkCombo" TargetType="ComboBox">
      <Setter Property="Height" Value="34"/>
      <Setter Property="Foreground" Value="#E9E9EC"/>
      <Setter Property="ItemContainerStyle" Value="{StaticResource ComboItem}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <ToggleButton x:Name="Tgl" Focusable="False" ClickMode="Press"
                            IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border x:Name="Bd" Background="#26262C" BorderBrush="#3A3A42" BorderThickness="1" CornerRadius="7">
                      <Path HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,12,0"
                            Data="M 0 0 L 5 5 L 10 0" Stroke="#9A9AA4" StrokeThickness="1.5"/>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True">
                        <Setter TargetName="Bd" Property="BorderBrush" Value="#4C4C57"/>
                      </Trigger>
                      <Trigger Property="IsChecked" Value="True">
                        <Setter TargetName="Bd" Property="BorderBrush" Value="#3D82F0"/>
                      </Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <ContentPresenter IsHitTestVisible="False" Content="{TemplateBinding SelectionBoxItem}"
                                Margin="12,0,32,0" VerticalAlignment="Center"
                                TextBlock.Foreground="#E9E9EC"/>
              <Popup IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" AllowsTransparency="True"
                     Focusable="False" PopupAnimation="Fade">
                <Border Background="#26262C" BorderBrush="#3A3A42" BorderThickness="1" CornerRadius="7"
                        MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}"
                        Margin="0,4,0,0" Padding="0,4">
                  <ScrollViewer MaxHeight="280">
                    <StackPanel IsItemsHost="True"/>
                  </ScrollViewer>
                </Border>
              </Popup>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- 선택목록 + 직접입력 (해상도·프레임·화질처럼 자주 쓰는 값이 있는 항목) -->
    <Style x:Key="EditCombo" TargetType="ComboBox">
      <Setter Property="Height" Value="34"/>
      <Setter Property="IsEditable" Value="True"/>
      <Setter Property="Foreground" Value="#E9E9EC"/>
      <Setter Property="ItemContainerStyle" Value="{StaticResource ComboItem}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <Border x:Name="Bd" Background="#26262C" BorderBrush="#3A3A42" BorderThickness="1" CornerRadius="7"/>
              <TextBox x:Name="PART_EditableTextBox" Background="Transparent" BorderThickness="0"
                       Foreground="#E9E9EC" CaretBrush="#E9E9EC" SelectionBrush="#2C6BD6"
                       Margin="11,0,34,0" VerticalAlignment="Center" VerticalContentAlignment="Center"/>
              <ToggleButton x:Name="Tgl" Width="32" HorizontalAlignment="Right" Focusable="False" ClickMode="Press"
                            IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border Background="Transparent">
                      <Path HorizontalAlignment="Center" VerticalAlignment="Center"
                            Data="M 0 0 L 5 5 L 10 0" Stroke="#9A9AA4" StrokeThickness="1.5"/>
                    </Border>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <Popup IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" AllowsTransparency="True"
                     Focusable="False" PopupAnimation="Fade">
                <Border Background="#26262C" BorderBrush="#3A3A42" BorderThickness="1" CornerRadius="7"
                        MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}"
                        Margin="0,4,0,0" Padding="0,4">
                  <ScrollViewer MaxHeight="280">
                    <StackPanel IsItemsHost="True"/>
                  </ScrollViewer>
                </Border>
              </Popup>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="#4C4C57"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocusWithin" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="#3D82F0"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- 토글 스위치 -->
    <Style x:Key="Toggle" TargetType="CheckBox">
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Border Background="Transparent" Padding="0,2">
              <Border x:Name="Track" Width="46" Height="26" CornerRadius="13"
                      Background="#3A3A42" HorizontalAlignment="Left">
                <Ellipse x:Name="Knob" Width="20" Height="20" Fill="#9A9AA4"
                         HorizontalAlignment="Left" Margin="3,0,0,0"/>
              </Border>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Track" Property="Background" Value="#2F72E0"/>
                <Setter TargetName="Knob" Property="Fill" Value="#FFFFFF"/>
                <Setter TargetName="Knob" Property="HorizontalAlignment" Value="Right"/>
                <Setter TargetName="Knob" Property="Margin" Value="0,0,3,0"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Track" Property="Opacity" Value="0.85"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- 버튼 : 파란 강조 -->
    <Style x:Key="Accent" TargetType="Button">
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="20,10"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="#2F72E0" CornerRadius="7" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#4183EC"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#255FC0"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- 버튼 : 보조 -->
    <Style x:Key="Ghost" TargetType="Button">
      <Setter Property="Foreground" Value="#D8D8DE"/>
      <Setter Property="Padding" Value="16,9"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="#26262C" BorderBrush="#3A3A42" BorderThickness="1"
                    CornerRadius="7" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#31313A"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="#4C4C57"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#1F1F25"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- 왼쪽 메뉴 -->
    <Style x:Key="NavItem" TargetType="ListBoxItem">
      <Setter Property="Foreground" Value="#A8A8B2"/>
      <Setter Property="FontSize" Value="13.5"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="Bd" Background="Transparent" BorderBrush="Transparent"
                    BorderThickness="3,0,0,0" Padding="19,11,16,11">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#26262C"/>
                <Setter Property="Foreground" Value="#E9E9EC"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#2A2A32"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="#3D82F0"/>
                <Setter Property="Foreground" Value="#FFFFFF"/>
                <Setter Property="FontWeight" Value="SemiBold"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

  </Window.Resources>

  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="56"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- ===== 헤더 ===== -->
    <Border Grid.Row="0" Background="#202026" BorderBrush="#2E2E36" BorderThickness="0,0,0,1">
      <Grid Margin="22,0">
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="scrcpy" FontSize="19" FontWeight="SemiBold" Foreground="#F0F0F3"/>
          <TextBlock Text="설정" FontSize="19" Foreground="#6E6E7A" Margin="9,0,0,0"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
          <Ellipse x:Name="DevDot" Width="9" Height="9" Fill="#4A4A52" Margin="0,0,9,0"/>
          <Button x:Name="BtnPair" Content="무선 페어링" Style="{StaticResource Ghost}" Margin="0,0,9,0"/>
          <ComboBox x:Name="CmbDevice" Width="230" Style="{StaticResource DarkCombo}"/>
          <Button x:Name="BtnRefresh" Content="새로고침" Style="{StaticResource Ghost}" Margin="9,0,0,0"/>
          <Button x:Name="BtnDiscover" Content="기기 찾기" Style="{StaticResource Ghost}" Margin="6,0,0,0"
                  ToolTip="폰을 같은 Wi-Fi 에서 찾아 자동으로 연결합니다 (케이블·폰 조작 불필요)"/>
        </StackPanel>
      </Grid>
    </Border>

    <!-- ===== 본문 ===== -->
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="176"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <Border Grid.Column="0" Background="#202026" BorderBrush="#2E2E36" BorderThickness="0,0,1,0">
        <ListBox x:Name="NavList" Background="Transparent" BorderThickness="0" Margin="0,12,0,0"
                 ItemContainerStyle="{StaticResource NavItem}"
                 ScrollViewer.HorizontalScrollBarVisibility="Disabled"/>
      </Border>

      <ScrollViewer Grid.Column="1" VerticalScrollBarVisibility="Auto" Padding="0,0,6,0">
        <StackPanel x:Name="OptionHost" Margin="30,24,24,28"/>
      </ScrollViewer>
    </Grid>

    <!-- ===== 하단 ===== -->
    <Border Grid.Row="2" Background="#202026" BorderBrush="#2E2E36" BorderThickness="0,1,0,0" Padding="22,16,22,18">
      <StackPanel>

        <StackPanel Orientation="Horizontal" Margin="0,0,0,12">
          <TextBlock Text="프리셋" Foreground="#8A8A94" VerticalAlignment="Center" Margin="0,0,10,0"/>
          <ComboBox x:Name="CmbPreset" Width="190" Style="{StaticResource DarkCombo}"/>
          <TextBox x:Name="TxtPresetName" Width="150" Style="{StaticResource DarkText}" Margin="8,0,0,0"
                   ToolTip="새 이름을 적고 저장을 누르면 새 프리셋이 됩니다"/>
          <Button x:Name="BtnPresetSave" Content="저장" Style="{StaticResource Ghost}" Margin="8,0,0,0"/>
          <Button x:Name="BtnPresetDel"  Content="삭제" Style="{StaticResource Ghost}" Margin="6,0,0,0"/>
          <TextBlock Text="직접 추가" Foreground="#8A8A94" VerticalAlignment="Center" Margin="22,0,10,0"/>
          <TextBox x:Name="TxtExtra" Width="230" Style="{StaticResource DarkText}" FontFamily="Consolas"/>
        </StackPanel>

        <TextBox x:Name="TxtCmd" Style="{StaticResource CmdBox}" Height="58" Margin="0,0,0,14"/>

        <StackPanel Orientation="Horizontal">
          <Button x:Name="BtnRun"  Content="실행"        Style="{StaticResource Accent}" Width="150"/>
          <Button x:Name="BtnCopy" Content="명령어 복사"  Style="{StaticResource Ghost}"  Margin="10,0,0,0"/>
          <Button x:Name="BtnBat"  Content=".bat 로 저장" Style="{StaticResource Ghost}"  Margin="8,0,0,0"/>
          <TextBlock x:Name="LblStatus" Foreground="#7E7E88" VerticalAlignment="Center" Margin="20,0,0,0"/>
        </StackPanel>

      </StackPanel>
    </Border>

  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xamlDoc
$win = [Windows.Markup.XamlReader]::Load($reader)

# 이름 있는 요소 꺼내기
$NavList       = $win.FindName('NavList')
$OptionHost    = $win.FindName('OptionHost')
$CmbDevice     = $win.FindName('CmbDevice')
$DevDot        = $win.FindName('DevDot')
$BtnPair       = $win.FindName('BtnPair')
$BtnRefresh    = $win.FindName('BtnRefresh')
$BtnDiscover   = $win.FindName('BtnDiscover')
$CmbPreset     = $win.FindName('CmbPreset')
$TxtPresetName = $win.FindName('TxtPresetName')
$BtnPresetSave = $win.FindName('BtnPresetSave')
$BtnPresetDel  = $win.FindName('BtnPresetDel')
$TxtExtra      = $win.FindName('TxtExtra')
$TxtCmd        = $win.FindName('TxtCmd')
$BtnRun        = $win.FindName('BtnRun')
$BtnCopy       = $win.FindName('BtnCopy')
$BtnBat        = $win.FindName('BtnBat')
$LblStatus     = $win.FindName('LblStatus')

$Controls = @{}
$Pages    = @{}
$script:Presets = @{}
$script:ready   = $false
$script:powerOptionsUpdating = $false
$script:stayAwakeBeforeScreenOff = $null
$script:noControlBeforeScreenOff = $null
# 기기 콤보는 사람이 읽을 라벨을 보여주고, scrcpy 에는 진짜 기기 ID 를 넘긴다.
$script:DeviceIdByLabel = @{}
$script:OfflineLabels   = [System.Collections.Generic.HashSet[string]]::new()

$StyleText  = $win.FindResource('DarkText')
$StyleCombo = $win.FindResource('DarkCombo')
$StyleEdit  = $win.FindResource('EditCombo')
$StyleToggle= $win.FindResource('Toggle')

$ColLabel = [Windows.Media.BrushConverter]::new().ConvertFromString('#E4E4E9')
$ColHint  = [Windows.Media.BrushConverter]::new().ConvertFromString('#76767F')
$ColTitle = [Windows.Media.BrushConverter]::new().ConvertFromString('#F0F0F3')
$ColGreen = [Windows.Media.BrushConverter]::new().ConvertFromString('#3FB950')
$ColGray  = [Windows.Media.BrushConverter]::new().ConvertFromString('#4A4A52')

# ---------- 그룹별 페이지 생성 ----------
foreach ($group in ($OPTIONS.Group | Select-Object -Unique)) {

    $panel = New-Object Windows.Controls.StackPanel

    $title = New-Object Windows.Controls.TextBlock
    $title.Text = $group
    $title.FontSize = 20
    $title.FontWeight = 'SemiBold'
    $title.Foreground = $ColTitle
    $title.Margin = '0,0,0,22'
    [void]$panel.Children.Add($title)

    foreach ($opt in ($OPTIONS | Where-Object { $_.Group -eq $group })) {

        $row = New-Object Windows.Controls.StackPanel
        $row.Margin = '0,0,0,20'

        $lbl = New-Object Windows.Controls.TextBlock
        $lbl.Text = $opt.Label
        $lbl.Foreground = $ColLabel
        $lbl.FontSize = 13.5
        $lbl.Margin = '0,0,0,7'
        [void]$row.Children.Add($lbl)

        $line = New-Object Windows.Controls.StackPanel
        $line.Orientation = 'Horizontal'

        $extraCtrl = $null   # 일부 항목은 컨트롤 옆에 버튼이 하나 더 붙는다 (예: 경로 [찾아보기])

        switch ($opt.Type) {
            'check' {
                $c = New-Object Windows.Controls.CheckBox
                $c.Style = $StyleToggle
                $c.IsChecked = [bool]$opt.Default
                $c.VerticalAlignment = 'Center'
                $c.Add_Checked({ Update-Preview })
                $c.Add_Unchecked({ Update-Preview })
            }
            'path' {
                # 실행 파일 경로 지정칸 + [찾아보기]. 고르면 config.json 에 바로 저장된다.
                # (다음 실행부터 적용 — 지금 떠 있는 세션의 $SCRCPY_EXE 를 바꾸지는 않는다)
                $c = New-Object Windows.Controls.TextBox
                $c.Style = $StyleText
                $c.Width = 330
                $c.Text = [string]$(if ($opt.Key -eq 'scrcpyPath') { $SCRCPY_EXE } else { $ADB_EXE })
                $c.Tag = $opt
                $c.Add_TextChanged({
                    param($s, $e)
                    $script:Config[$s.Tag.Key] = $s.Text.Trim()
                    $null = Write-Config $script:Config
                })

                $extraCtrl = New-Object Windows.Controls.Button
                $extraCtrl.Content = '찾아보기'
                $extraCtrl.Style = $win.FindResource('Ghost')
                $extraCtrl.Margin = '8,0,0,0'
                $extraCtrl.Tag = $c
                $extraCtrl.Add_Click({
                    param($s, $e)
                    $box = $s.Tag
                    $dlg = New-Object Microsoft.Win32.OpenFileDialog
                    $dlg.Filter = '실행 파일 (*.exe)|*.exe'
                    if ($box.Text -and (Test-Path $box.Text)) {
                        $dlg.FileName = Split-Path $box.Text -Leaf
                        $dlg.InitialDirectory = Split-Path $box.Text -Parent
                    }
                    if ($dlg.ShowDialog()) {
                        $box.Text = $dlg.FileName
                        $LblStatus.Text = '저장했습니다. 다음 실행부터 적용됩니다.'
                    }
                })
            }
            'phonepref' {
                # 폰 설정을 직접 바꾸는 토글. 현재 값은 시작할 때 폰에서 읽어온다.
                # Add_Click 을 쓰는 이유: Checked/Unchecked 는 코드로 값을 넣을 때도 발동해서
                # 초기화 중에 폰 설정을 덮어써 버린다. Click 은 사람이 누를 때만 발동.
                $c = New-Object Windows.Controls.CheckBox
                $c.Style = $StyleToggle
                $c.VerticalAlignment = 'Center'
                $c.Tag = $opt
                $c.Add_Click({
                    param($s, $e)
                    $o = $s.Tag
                    $v = if ($s.IsChecked) { '1' } else { '0' }
                    $approved = [Windows.MessageBox]::Show(
                        "휴대폰 설정을 직접 바꿉니다.`n`n$($o.Label): " + $(if ($s.IsChecked) { '켬' } else { '끔' }) +
                        "`n되돌리기: 이 토글을 다시 반대로 바꾸세요.`n`n계속할까요?",
                        '휴대폰 설정 변경 확인', 'YesNo', 'Warning')
                    if ($approved -ne [Windows.MessageBoxResult]::Yes) {
                        $s.IsChecked = -not [bool]$s.IsChecked
                        return
                    }
                    try {
                        & $ADB_EXE shell settings put $o.SettingNs $o.SettingKey $v 2>$null | Out-Null
                        $LblStatus.Text = "폰 설정 반영: $($o.Label) = " + $(if ($s.IsChecked) { '켬' } else { '끔' })
                    } catch {
                        $LblStatus.Text = "폰 설정 변경 실패 — 기기 연결을 확인하세요"
                    }
                })
            }
            'combo' {
                $c = New-Object Windows.Controls.ComboBox
                $c.Style = $StyleCombo
                $c.Width = 210
                foreach ($i in $opt.Items) { [void]$c.Items.Add($i) }
                $c.SelectedItem = $opt.Default
                $c.Add_SelectionChanged({ Update-Preview })
            }
            'editcombo' {
                # 목록에서 고를 수도, 직접 칠 수도 있는 칸.
                # ※ 여기서 편집칸 Text 를 코드로 다시 쓰면 안 된다 — WPF 는 선택 처리 도중 Text 를
                #   건드리면 선택이 풀리면서 칸이 비어버린다(실측). 그래서 목록 항목은 값 그대로만 넣는다.
                $c = New-Object Windows.Controls.ComboBox
                $c.Style = $StyleEdit
                $c.Width = 210
                foreach ($i in $opt.Items) { [void]$c.Items.Add($i) }
                $c.Text = [string]$opt.Default
                $c.Add_SelectionChanged({ Update-Preview })
                $c.Add_KeyUp({ Update-Preview })
            }
            default {
                $c = New-Object Windows.Controls.TextBox
                $c.Style = $StyleText
                $c.Width = 210
                $c.Text = [string]$opt.Default
                $c.Add_TextChanged({ Update-Preview })
            }
        }
        [void]$line.Children.Add($c)
        if ($extraCtrl) { [void]$line.Children.Add($extraCtrl) }

        $hint = New-Object Windows.Controls.TextBlock
        $hint.Text = $opt.Hint
        $hint.Foreground = $ColHint
        $hint.FontSize = 12
        $hint.VerticalAlignment = 'Center'
        $hint.Margin = '14,0,0,0'
        $hint.TextWrapping = 'Wrap'
        $hint.MaxWidth = 380
        [void]$line.Children.Add($hint)

        [void]$row.Children.Add($line)
        [void]$panel.Children.Add($row)

        $Controls[$opt.Key] = $c
    }

    if ($group -eq '설정') {
        $install = New-Object Windows.Controls.StackPanel
        $install.Margin = '0,10,0,0'

        $installTitle = New-Object Windows.Controls.TextBlock
        $installTitle.Text = '공식 scrcpy 설치'
        $installTitle.Foreground = $ColLabel
        $installTitle.FontSize = 13.5
        $installTitle.Margin = '0,0,0,7'
        [void]$install.Children.Add($installTitle)

        $installRootLabel = New-Object Windows.Controls.TextBlock
        $installRootLabel.Text = '설치 폴더 (선택한 폴더 아래에 버전별 폴더를 만듭니다)'
        $installRootLabel.Foreground = $ColHint
        $installRootLabel.FontSize = 12
        $installRootLabel.Margin = '0,0,0,7'
        [void]$install.Children.Add($installRootLabel)

        $installRootLine = New-Object Windows.Controls.StackPanel
        $installRootLine.Orientation = 'Horizontal'

        $installRootBox = New-Object Windows.Controls.TextBox
        $installRootBox.Style = $StyleText
        $installRootBox.Width = 330
        $installRootBox.Text = [string]$(if ($script:Config.ContainsKey('installRoot') -and $script:Config.installRoot) { $script:Config.installRoot } else { $DEFAULT_SCRCPY_INSTALL_ROOT })
        $installRootBox.Add_TextChanged({
            param($s, $e)
            $script:Config['installRoot'] = $s.Text.Trim()
            $null = Write-Config $script:Config
        })
        $script:InstallRootBox = $installRootBox
        [void]$installRootLine.Children.Add($installRootBox)

        $installRootBrowse = New-Object Windows.Controls.Button
        $installRootBrowse.Content = '설치 폴더 선택'
        $installRootBrowse.Style = $win.FindResource('Ghost')
        $installRootBrowse.Margin = '8,0,0,0'
        $installRootBrowse.Tag = $installRootBox
        $installRootBrowse.Add_Click({
            param($s, $e)
            Add-Type -AssemblyName System.Windows.Forms
            $box = $s.Tag
            $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
            $dlg.Description = 'scrcpy 버전별 설치 폴더를 만들 위치를 고르세요.'
            if ($box.Text -and (Test-Path -LiteralPath $box.Text)) { $dlg.SelectedPath = $box.Text }
            if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $box.Text = $dlg.SelectedPath }
        })
        [void]$installRootLine.Children.Add($installRootBrowse)

        [void]$install.Children.Add($installRootLine)

        $installLine = New-Object Windows.Controls.StackPanel
        $installLine.Orientation = 'Horizontal'

        $installButton = New-Object Windows.Controls.Button
        $installButton.Content = '공식 최신 버전 설치'
        $installButton.Style = $win.FindResource('Ghost')
        $installButton.Add_Click({ Install-OfficialScrcpy })
        [void]$installLine.Children.Add($installButton)

        $guideButton = New-Object Windows.Controls.Button
        $guideButton.Content = '설치 안내 열기'
        $guideButton.Style = $win.FindResource('Ghost')
        $guideButton.Margin = '8,0,0,0'
        $guideButton.Add_Click({
            $guidePath = Join-Path $ProjectRoot 'scrcpy-install-guide.html'
            if (-not (Test-Path -LiteralPath $guidePath)) {
                [void][Windows.MessageBox]::Show(
                    "설치 안내 파일을 찾지 못했습니다.`n`n경로: $guidePath",
                    'scrcpy 설치 안내', 'OK', 'Error')
                return
            }
            try {
                # 사용자가 직접 누른 버튼으로만 기본 브라우저를 열며, 설치·다운로드는 시작하지 않는다.
                Start-Process -FilePath $guidePath -ErrorAction Stop
            } catch {
                [void][Windows.MessageBox]::Show(
                    "설치 안내를 열지 못했습니다.`n`n$($_.Exception.Message)",
                    'scrcpy 설치 안내', 'OK', 'Error')
            }
        })
        [void]$installLine.Children.Add($guideButton)

        $installHint = New-Object Windows.Controls.TextBlock
        $installHint.Text = 'Genymobile GitHub 릴리스만 사용합니다. 다운로드 전에 버전·출처·SHA-256 검증·설치 경로를 확인합니다.'
        $installHint.Foreground = $ColHint
        $installHint.FontSize = 12
        $installHint.VerticalAlignment = 'Center'
        $installHint.Margin = '14,0,0,0'
        $installHint.TextWrapping = 'Wrap'
        $installHint.MaxWidth = 380
        [void]$installLine.Children.Add($installHint)

        [void]$install.Children.Add($installLine)
        [void]$panel.Children.Add($install)
    }

    $Pages[$group] = $panel
    [void]$NavList.Items.Add($group)
}
