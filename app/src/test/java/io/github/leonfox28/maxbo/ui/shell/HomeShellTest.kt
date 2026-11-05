package io.github.leonfox28.maxbo.ui.shell

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.printToString
import io.github.leonfox28.maxbo.MaxboApp
import io.github.leonfox28.maxbo.support.testGraph
import org.junit.Assert.assertFalse
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class HomeShellTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Before
    fun setUp() {
        compose.setContent { MaxboApp(testGraph()) }
    }

    private fun tab(label: String) = compose.onNodeWithContentDescription(label)

    @Test
    fun `opens on the home tab`() {
        tab("首页").assertIsSelected()
        compose.onNodeWithText("主题").assertDoesNotExist()
        // Signed out, there is nobody to post as.
        tab("发微博").assertDoesNotExist()
    }

    @Test
    fun `switches tabs from the pill`() {
        tab("设置").performClick()
        tab("设置").assertIsSelected()
        compose.onNodeWithText("主题").assertExists()

        tab("首页").performClick()
        tab("首页").assertIsSelected()
        compose.onNodeWithText("主题").assertDoesNotExist()
    }

    @Test
    fun `screen readers get one node per tab, with no tooltip of its own`() {
        tab("搜索").assert(SemanticsMatcher.expectValue(SemanticsProperties.Selected, false))
        val tree = compose.onRoot(useUnmergedTree = true).printToString()
        assertFalse(tree, tree.contains("OnLongClick"))
    }

    @Test
    fun `opens text size over settings and closes it again`() {
        tab("设置").performClick()
        compose.onNodeWithText("字体大小").performClick()
        compose.onNodeWithContentDescription("返回").assertExists()
        tab("设置").assertDoesNotExist()

        compose.onNodeWithContentDescription("返回").performClick()
        tab("设置").assertIsSelected()
        compose.onNodeWithContentDescription("返回").assertDoesNotExist()
    }

    @Test
    fun `system back closes the page, back to the tab it was opened from`() {
        tab("设置").performClick()
        compose.onNodeWithText("字体大小").performClick()
        compose.onNodeWithContentDescription("返回").assertExists()
        compose.runOnUiThread { compose.activity.onBackPressedDispatcher.onBackPressed() }

        tab("设置").assertIsSelected()
        compose.onNode(hasText("主题")).assertExists()
    }

    @Test
    fun `screen readers can tap the open tab again`() {
        tab("首页").assert(SemanticsMatcher.keyIsDefined(SemanticsActions.CustomActions))
        tab("设置").assert(SemanticsMatcher.keyNotDefined(SemanticsActions.CustomActions))
    }
}
