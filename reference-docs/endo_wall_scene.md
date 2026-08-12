# Endo at the Wall — Scene Dialogue

Scene-level dialogue script for the Endo barrier-maintenance beat between Mother Flure chamber exit and shelter 6 arrival. Bridges the Mother Flure chamber (Section 7 of the chamber dialogue) and the Processing Stacks scene.

Companion to `mother_flure_dialogue.md`, `nustle_dialogue.md`, and `dead_flure_dialogue.md`.

Placement: Corridor traversal between the Mother Flure offshoot and shelter 6 (entry to Processing Stacks). Act 1, between shelters 5 and 6. Party composition: Aster, Peris, Endo (Endo still present; his departure comes at shelter 6-7).

Scene plays in this order:

1. Leaving the chamber corridor
2. The stressed barrier section
3. Endo stops to work
4. The party waits (Peris reads Endo, Aster reads Peris)
5. Aster processes Mother Flure in data-frame; Peris translates
6. Endo finishes
7. Continuing

Style notes per the project conventions:
- No em dashes
- Endo: silent, communicates through action, every gesture load-bearing. No spoken lines in this scene. His communication is entirely physical.
- Aster: still processing the chamber. Data-mode observations, but shadowed by the experience he just had. Opens a window to Peris by asking her a question.
- Peris: reads Endo immediately. Translates Aster's data observation into her frame. Has an "arrow flip" moment where Aster names her behavior for her.

The scene's job:
- Characterize Endo through silent action, before his departure
- Seed his wall (the specific piece of barrier he maintains) as a place he has, which sets up him returning to it at shelter 6-7
- Give Peris a moment of being observed rather than observing
- Carry forward the Mother Flure processing into the walking-conversation register
- Bridge into shelter 6

## 1. Leaving the chamber corridor

[Setting: the offshoot corridor out of the Mother Flure chamber. The party is walking in single file. Endo ahead, Aster and Peris behind. The flure's post-bloom chemistry still hangs in the air — Peris's clothes have picked up the scent, and the corridor itself is warmer for a while after the bloom. Aster's data overlay is mostly idle. He has not said anything since exiting the chamber.]

endo_wall.entry.narration | | normal | false | The party walks back up the offshoot corridor from the Mother Flure chamber. Endo ahead, Aster and Peris behind. The air is warmer than it was before they entered. The post-bloom chemistry lingers on Peris's clothes and in the corridor itself. Aster has not spoken since they left the chamber. | Scene opens

endo_wall.entry.peris.look | | normal | false | Peris glances at Aster. She does not say anything. She has been glancing at him every minute or so since they left the chamber. He does not notice. | Physical setup for the arrow-flip beat later

## 2. The stressed barrier section

[Setting: the offshoot rejoins the main corridor. They continue toward shelter 6. After a short walk, they pass a section where the corridor wall shows visible stress: the biological texture of the barrier is uneven, with a patch where the normal surface has thinned. Aster's overlay picks it up.]

endo_wall.barrier.narration | | normal | false | The corridor opens out from the offshoot. They walk toward shelter 6. After a short distance the wall on the left shows stress: an uneven patch in the biological texture, a section where the barrier has thinned. | Physical marker before Endo stops

endo_wall.barrier.aster.overlay | Aster | data | false | Barrier integrity at sixty-one. Dropping about one percent per minute. This is stressed, not failing, but it wants attention. | His overlay read. He is still in data-mode, but quietly.

## 3. Endo stops to work

[Setting: Endo stops walking. He does not announce it. He does not turn toward the party. He turns toward the wall, walks the few steps to it, and places his hands on the surface where the thinning is. He begins to work. His hands move deliberately, precisely. The movements are not big. They are small, practiced, continuous.]

endo_wall.stop.narration | | normal | false | Endo stops. He does not turn toward the party or say anything. He walks to the stressed section of the wall, places his hands on it, and begins to work. His hands move in small, practiced motions. | The first silent action

endo_wall.stop.aster.confused | Aster | normal | false | Endo? | Not alarmed. Asking what is happening.

endo_wall.stop.peris.naming | Peris | normal | false | He's working. | Flat. She saw it immediately. She does not need to explain more than this.

endo_wall.stop.aster.overlay | Aster | data | false | ...The barrier integrity just ticked up. Sixty-two. Sixty-three. He's stabilizing it. How is he stabilizing it? | His overlay confirming what his eyes were about to miss.

endo_wall.stop.peris.sit | | normal | false | Peris sits down near the wall, a comfortable distance from Endo. She unhooks her pack and pulls out a small piece of food. She is settling in to wait. She does this without asking. | Physical confirmation that she already knew

endo_wall.stop.aster.follow | | normal | false | Aster looks at Peris sitting. He looks at Endo working. He sits down near Peris, more hesitantly. | He is following her read

## 4. The party waits

[Setting: Endo continues working. His hands move on the wall. Slowly, methodically. The camera should hold on him working for a beat longer than dialogue pacing would normally allow. The player watches someone do infrastructure work. Peris is watching Endo. Aster is watching Peris watching Endo. The composition is a small triangle: Endo at the wall, Peris looking at him, Aster looking at her.]

endo_wall.wait.narration | | normal | false | Endo works. His hands move on the wall. The texture under his hands begins to even out — the thinned patch slowly thickens, the unevenness smooths. Peris watches him. Aster watches Peris. Time passes. | The composition and the waiting

endo_wall.wait.aster.question | Aster | normal | false | How did you know he was going to stop? | Quiet. Genuine question.

endo_wall.wait.peris.saw | Peris | normal | false | He saw the wall. | Simple.

endo_wall.wait.aster.saw_too | Aster | data | false | I saw the wall. The overlay flagged it. | Not argumentative. Trying to understand the gap between her read and his.

endo_wall.wait.peris.different | Peris | normal | false | You saw a number. He saw the wall. | She is not making the distinction to be clever. She is naming what she noticed.

endo_wall.wait.aster.beat | | normal | false | Aster looks at the wall. He looks at Endo's hands on it. He looks back at Peris. He does not speak for a moment. | Recognition beat

## 5. Aster observes Peris (the arrow flip)

[Setting: they are still waiting. Endo is still working. Aster is looking at Peris. She has been watching Endo the whole time. She has not taken her eyes off him. Aster notices this.]

endo_wall.flip.aster.notice | Aster | normal | false | You've been watching him. | Quiet observation.

endo_wall.flip.peris.mm | Peris | normal | false | Mm. | Not confirming, not denying. She did not consciously register she was doing this.

endo_wall.flip.aster.specific | Aster | normal | false | Since we left the chamber. Every time I looked over. You were watching him. | Specifying, so she knows he is observing a pattern.

endo_wall.flip.peris.beat | | normal | false | Peris looks down at her hands. She does not respond immediately. She is noticing her own attention for the first time. | The arrow flip lands

endo_wall.flip.peris.huh | Peris | normal | false | ...Huh. | Quiet. She did not know.

endo_wall.flip.aster.careful | Aster | normal | false | Why? | Not pushing. Asking because he is curious and because he thinks the answer might matter.

endo_wall.flip.peris.dont_know | Peris | normal | false | I don't know. | Honest. She does not have the answer yet.

endo_wall.flip.peris.adding | Peris | normal | false | I've just been... watching him. | Giving him what she has, which is not much.

endo_wall.flip.aster.beat | | normal | false | Aster does not push further. He has given her the observation. What she does with it is hers. | The restraint is the care

## 6. Mother Flure in data-frame; Peris translates

[Setting: they continue to wait. Endo continues to work. Aster has been holding something since the chamber. He finds space to say it now.]

endo_wall.process.aster.readings | Aster | data | false | The mother's iron uptake was at one forty percent of baseline. In the chamber. | He is starting somewhere he knows how to start.

endo_wall.process.peris.listening | Peris | normal | false | Yeah? | Inviting him to continue

endo_wall.process.aster.impossible | Aster | data | false | Cellular senescence at that stress level caps organisms at a fraction of a normal lifespan. The models predict a few cycles. Maybe a dozen. She has been at one forty for... the terminal said decades. | He is getting at something.

endo_wall.process.peris.wait | Peris | normal | false | So the models are wrong? | Gentle prompting.

endo_wall.process.aster.no | Aster | data | false | The models aren't wrong. The models are good. Something else is happening that the models don't account for. | He is being precise.

endo_wall.process.peris.translate | Peris | normal | false | She wanted to stay. | Plain. Her frame.

endo_wall.process.aster.pause | | normal | false | Aster does not answer immediately. | Recognition again

endo_wall.process.aster.doesnt_measure | Aster | data | false | The data doesn't measure wanting. | He is being careful. Not dismissing.

endo_wall.process.peris.know | Peris | normal | false | I know. | Acknowledging his constraint.

endo_wall.process.aster.but | Aster | normal | false | But you think she wanted to. | He is asking her to elaborate, not challenging her.

endo_wall.process.peris.evidence | Peris | normal | false | She stayed. That's what wanting to looks like. | Her epistemology. It is consistent with his data. It just adds something his data cannot see.

endo_wall.process.aster.beat | | normal | false | Aster considers this. His overlay is still active. He is looking at Endo working. | Allowing the thought to settle

endo_wall.process.aster.models | Aster | normal | false | I don't think the models account for that. | Quiet admission. Not a conversion. A recognition.

endo_wall.process.peris.smile | Peris | normal | false | No. Probably not. | Small. Not triumphant.

## 7. Endo finishes

[Setting: Endo lowers his hands from the wall. He steps back. The texture is smooth now, the thinning is resolved. Aster's overlay, peripheral in the frame, shows barrier integrity stabilized at a healthy level and holding. Endo stands looking at the wall for a beat. Then he turns to the party.]

endo_wall.finish.narration | | normal | false | Endo lowers his hands from the wall and steps back. The barrier surface is even, the thinned section filled in, the stress resolved. He stands looking at the wall for a beat longer than the work required. Then he turns toward the party. | Closure gesture

endo_wall.finish.aster.overlay | Aster | data | false | Integrity at ninety-four percent. Holding. | Data confirmation, quiet

endo_wall.finish.aster.stand | | normal | false | Aster stands. Peris stands. | Physical acknowledgment that the work is done

endo_wall.finish.aster.thanks | Aster | normal | false | Thanks, Endo. | Short. Sincere.

endo_wall.finish.endo.nod | | normal | false | Endo nods. He does not speak. | His acknowledgment

endo_wall.finish.peris.good | Peris | normal | false | You're good at this. | Quiet. Direct to Endo.

endo_wall.finish.endo.second_nod | | normal | false | Endo nods again. Something in his posture is slightly different from the first nod — fractionally more settled, fractionally more present. He does not speak. | Silent character beat

## 8. Continuing

[Setting: the party continues down the corridor toward shelter 6. Endo ahead again, scouting. Aster and Peris walking together. Neither speaks for a while. The barrier behind them holds. It will keep holding.]

endo_wall.continue.narration | | normal | false | The party continues toward shelter 6. Endo walks ahead again. Aster and Peris walk together. The barrier behind them holds. Nobody in the future walking past this section will know who stabilized it. | Closing narration; seeds Endo's upcoming departure

endo_wall.continue.peris.quiet | Peris | normal | false | (to Aster, quietly) He's not going to stay with us. | Small realization, not dramatic. She has been watching him. She understands.

endo_wall.continue.aster.look | Aster | normal | false | What? | He did not expect this observation.

endo_wall.continue.peris.wall | Peris | normal | false | He has a wall. That's where he belongs. | Final observation. She has read his intent before he has announced it.

endo_wall.continue.aster.process | | normal | false | Aster is quiet. He looks ahead at Endo. He does not know what to say. | Accepting the observation without knowing what to do with it

endo_wall.continue.narration.close | | normal | false | They continue toward shelter 6. The air cools slightly as the Mother Flure's post-bloom chemistry fades from their clothes. | Scene ends; transitions into shelter 6 arrival

# Pacing notes for the implementation team

**Register:**

Mixed. The walking beats (entry, continuing) can play in gameplay-register, with players moving through the environment while dialogue plays. The waiting beats (from Endo stopping through Endo finishing) play in cutscene-register — composed camera, deliberate positioning, the triangle composition of Endo at the wall + Peris watching Endo + Aster watching Peris. Total scene runs approximately 2-3 minutes from Endo stopping to the party continuing.

**The waiting pause:**

The actual barrier maintenance should take real screen time. When Endo stops working and his hands are moving on the wall, the camera should hold on him for 15-25 seconds before cutting to Aster and Peris's conversation. The player watches someone work. This is important: Endo's character has been sketched in silence so far, and this is the first sustained view of what he actually does. Rushing this beat undercuts his entire arc.

During the Aster-Peris conversation, the camera can alternate between the conversation and cutaway shots of Endo still working. He does not finish until the Aster-Peris dialogue completes. The timing is the scene's rhythm.

**The arrow-flip beat (section 5):**

This is the moment where Aster observes Peris instead of Peris observing someone else. It lands because the game has established the usual direction (Peris reads, Aster translates). Implementation should make Peris's "I don't know" and "Huh" feel genuinely new to her — she is noticing her own attention for the first time. Voice direction: Peris should sound slightly disoriented by the observation, like someone who caught a reflection of themselves unexpectedly. Not distressed. Just unfamiliar.

**Endo's two nods:**

The first nod (after Aster's "Thanks, Endo") is a standard Endo response. The second nod (after Peris's "You're good at this") is fractionally different. Posture, timing, angle — something that reads as "pleased" or "acknowledged" without being a facial expression the game needs to render. This is character work through body language at the limits of what a silent character can communicate. The animators should have the latitude to workshop the two nods until they read as distinct.

**Peris's final observation ("He's not going to stay with us"):**

This seeds Endo's departure at shelter 6-7. Peris has read his intent from the duration of his gaze at the wall. She speaks the observation quietly, privately to Aster. She is not warning the party. She is telling one person that she has noticed something. Aster does not know what to do with it. The scene ends before they resolve it, which is right: the resolution is Endo's actual departure a couple of shelters later.

**What Endo communicates:**

Endo has no spoken lines in this scene. His communication is entirely physical:
- Stopping without announcement
- Walking to the wall
- Placing his hands on it
- Working methodically
- Stepping back when done
- Holding his gaze on the wall for a beat
- Turning to the party
- Nodding (twice, with fractional difference)

This is a full character arc in gestures. The implementation team should treat his movement design in this scene as dialogue and workshop it accordingly.

**Voice direction:**

Aster: the scene opens with him quiet (unusual for him). His first data-mode line after Endo starts working is quiet, thoughtful, not clinical. His "How did you know he was going to stop?" should sound curious and humble, not testing her. His question to Peris about her attention ("You've been watching him") should be careful, not accusatory — he is offering her an observation, not challenging her. His mother-flure processing beats (section 6) return him to data-mode but softly, and his "I don't think the models account for that" should sound genuinely uncertain, not rhetorical.

Peris: her "He's working" and "He saw the wall" should be delivered as statements of fact, not as insights she is proud of. Her "She wanted to stay" should sound calm, grounded, not performative. Her "Huh" in the arrow-flip moment should be the sound of genuine surprise at a small thing. Her final observation about Endo not staying should be quiet and a little sad, but not dramatic.

**What the scene does not do:**

- Does not name Endo's upcoming departure as a decision he has made. Peris observes the direction he is going; she does not know when. Endo has not decided openly yet.
- Does not resolve Aster's Mother Flure processing. The "she wanted to stay" translation is an opening, not a closure. Aster carries the seed of this into later scenes.
- Does not explicitly flag the arrow-flip as important. Peris's "Huh" is the whole beat. The game does not tell the player "this is significant." Players who pay attention register it.
- Does not have Endo speak. Under any conditions. If anyone on the implementation team proposes giving Endo a line in this scene, the answer is no. He has exactly the communication channels he has throughout the game; those channels are enough.

# What this scene sets up

**Endo's departure (shelter 6-7):** When Endo leaves the party at shelter 6 or 7, the player has seen him do the thing he is going back to do. His departure is not abandonment; it is return. Peris already named it. The player is ready for it.

**Aster's Mother Flure processing:** The "she wanted to stay" framing plants a question in Aster's head that the Glass Bead Game simulation never asked him. Later scenes can pull on this thread when Aster encounters other persistence-past-expected-failure situations (Oli's maintenance work, Myke's infrastructure longevity, the workers in the Archive Depths).

**The romance balance flip:** This is the first scene where Aster observes Peris and names something she had not noticed about herself. The pattern inverts the usual direction. Later scenes can do more of this. The seed is the "You've been watching him" beat.

**The Endo-Peris reading line:** Peris reads Endo consistently throughout the scene. This establishes her as the party member most attuned to him. If Endo has any later callback beats (reappearance, return, communication), Peris should be the point of contact. She has the bandwidth for his silence.

# Open questions

- Whether Endo's barrier-maintenance work should be interactive (the player can assist via Aster hacking or Peris flora tending) or strictly observational (the party watches; the player has no input). Default: observational for this scene. Endo does the work alone because the work is his. Later barrier-crossing scenes can have composition-dependent approaches.
- Whether the arrow-flip beat should include a small mechanical element (a UI moment where Peris's perception layer briefly shifts to show herself, or similar) or remain purely dialogue-driven. Default: dialogue only. Do not overteach.
- Whether Peris's "He's not going to stay with us" line should be audible only to Aster (quiet delivery, proximity) or should be in-world audible to Endo too (he hears it but does not respond). Both have merit. Default: audible only to Aster. It is a private observation between two party members about a third.
- Whether the scene should include a brief interaction option where the player can choose to have Aster or Peris do something during the waiting (rest, check inventory, talk to Endo). Default: no such options. The waiting is the work. Interactivity during it would undercut the register.
