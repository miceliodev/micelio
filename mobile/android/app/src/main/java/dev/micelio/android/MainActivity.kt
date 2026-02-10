package dev.micelio.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import dev.micelio.android.ui.theme.MicelioTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MicelioTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    MicelioApp()
                }
            }
        }
    }
}
