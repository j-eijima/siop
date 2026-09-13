package jp.co.pendako.siop.app

import android.app.Application
import androidx.lifecycle.SavedStateHandle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * A request waiting for the user outlives the app's process: the model is
 * lost with the process, its saved state is not. Played out here by handing
 * a new model the saved state an old one left.
 */
@RunWith(AndroidJUnit4::class)
class SessionModelTest {
    private val application =
        InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as Application

    private val requestUrl =
        "openid://?response_type=id_token&scope=openid&nonce=n1&client_id=https%3A%2F%2Fclient.example.org%2Fcb"

    @Test
    fun aRequestWaitingForTheUserIsTakenUpAgainAfterTheProcessEnds() {
        val saved = SavedStateHandle()
        SessionModel(application, saved).session.receive(requestUrl)

        val restored = SessionModel(application, saved).session

        val phase = restored.phase
        assertTrue("待っていたリクエストが消えている: $phase", phase is AuthenticationSession.Phase.Consent)
        assertEquals("n1", (phase as AuthenticationSession.Phase.Consent).request.nonce)
    }

    @Test
    fun anAnsweredRequestIsNotOfferedAgain() {
        val saved = SavedStateHandle()
        val session = SessionModel(application, saved).session
        session.receive(requestUrl)
        session.decline((session.phase as AuthenticationSession.Phase.Consent).request) { true }

        assertNull(saved[SessionModel.PENDING_REQUEST])
        assertTrue(SessionModel(application, saved).session.phase is AuthenticationSession.Phase.Idle)
    }
}
