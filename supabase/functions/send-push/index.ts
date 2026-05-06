import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.7.1'
import { initializeApp, cert } from 'npm:firebase-admin@11.11.0/app'
import { getMessaging } from 'npm:firebase-admin@11.11.0/messaging'

// Parse the service account JSON from the Supabase Secrets
const serviceAccountString = Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ?? '{}';

try {
  const serviceAccount = JSON.parse(serviceAccountString);
  initializeApp({
    credential: cert(serviceAccount)
  });
} catch (error) {
  console.error("Failed to initialize Firebase Admin:", error);
}

serve(async (req) => {
  try {
    const payload = await req.json()
    const newMessage = payload.record 
    
    const senderId = newMessage.user_id;
    const matchId = newMessage.match_id;
    const content = newMessage.content;

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Find all users in this match/group chat EXCEPT the sender
    const { data: groupMembers, error: memberError } = await supabaseClient
      .from('group_members')
      .select('user_id')
      .eq('group_id', matchId)
      .neq('user_id', senderId)

    if (memberError || !groupMembers || groupMembers.length === 0) {
      return new Response(JSON.stringify({ message: "No recipients found" }), { status: 200 })
    }

    const recipientIds = groupMembers.map(m => m.user_id)

    // Fetch the FCM tokens for these recipients
    const { data: tokens, error: tokenError } = await supabaseClient
      .from('fcm_tokens')
      .select('token')
      .in('user_id', recipientIds)

    if (tokenError || !tokens || tokens.length === 0) {
      return new Response(JSON.stringify({ message: "No tokens found" }), { status: 200 })
    }

    // Send push notifications via modern Firebase Admin SDK (HTTP v1)
    const tokenStrings = tokens.map(t => t.token);

    const messagePayload = {
      notification: {
        title: "New message in your group",
        body: content,
      },
      data: {
        type: "chat",
        match_id: matchId,
      },
      tokens: tokenStrings,
    };

    const response = await getMessaging().sendMulticast(messagePayload);
    console.log(response.successCount + ' messages were sent successfully');

    return new Response(JSON.stringify({ success: true, sent: response.successCount }), { headers: { "Content-Type": "application/json" } })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  }
})
