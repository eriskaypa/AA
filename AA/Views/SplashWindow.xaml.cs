using System;
using System.IO;
using System.Windows;
using System.Windows.Media.Imaging;

namespace AA.Views;

/// <summary>Startup loading screen. Shows the bundled splash photo (Assets/Splash.png) if present,
/// otherwise a simple text fallback so the app still runs before the image is added.</summary>
public partial class SplashWindow : Window
{
    public SplashWindow()
    {
        InitializeComponent();
        LoadSplashImage();
    }

    private void LoadSplashImage()
    {
        try
        {
            var uri = new Uri("pack://application:,,,/Assets/Splash.png", UriKind.Absolute);
            var res = Application.GetResourceStream(uri);
            if (res == null) throw new FileNotFoundException("Splash resource missing.");
            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.CacheOption = BitmapCacheOption.OnLoad;
            bmp.StreamSource = res.Stream;
            bmp.EndInit();
            bmp.Freeze();
            SplashImage.Source = bmp;
            FallbackPanel.Visibility = Visibility.Collapsed;
        }
        catch
        {
            // No bundled image yet — show the text fallback.
            SplashImage.Visibility = Visibility.Collapsed;
            FallbackPanel.Visibility = Visibility.Visible;
        }
    }
}
