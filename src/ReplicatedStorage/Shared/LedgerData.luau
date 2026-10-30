--!nonstrict
-- LedgerData (v2.1): what can be written in the BLACK LEDGER. The ledger is a black notebook; its shikigami Kuro (black, only the
-- holder sees and hears him) lives behind whoever holds it. Write a name (pick the FACE, then write the NAME), choose how
-- they die. Every cause below is played out by LedgerService.

local LedgerData = {}

LedgerData.Causes = {
	{ id = "crash", name = "Car crash", blurb = "A car comes out of nowhere." },
	{ id = "trip", name = "Trips and breaks their neck", blurb = "One banana peel. One bad step." },
	{ id = "heart", name = "Heart attack", blurb = "The heart simply stops." },
	{ id = "fall", name = "Falls from the sky", blurb = "Taken up high. Dropped." },
	{ id = "lightning", name = "Struck by lightning", blurb = "A clear sky, a single bolt." },
	{ id = "anvil", name = "Anvil", blurb = "Classic. Heavy. Final." },
	{ id = "piano", name = "Falling piano", blurb = "At least it is in tune." },
	{ id = "burn", name = "Bursts into flames", blurb = "From the inside out." },
	{ id = "explode", name = "Explodes", blurb = "A very short fuse." },
	{ id = "choke", name = "Chokes on an apple", blurb = "Kuro's favourite." },
	{ id = "freeze", name = "Freezes and shatters", blurb = "Cold. Brittle. Gone." },
	{ id = "ash", name = "Turns to ash", blurb = "The wind takes the rest." },
	{ id = "ink", name = "Dissolves into black ink", blurb = "Written out of the story." },
}
LedgerData.ById = {} :: { [string]: { id: string, name: string, blurb: string } }
for _, c in LedgerData.Causes do
	LedgerData.ById[c.id] = c
end

-- the rules, as printed on the first page
LedgerData.Rules = {
	"The one whose name is written in this ledger, while the writer pictures their face, meets the fate written beside it.",
	"First the FACE, then the NAME. A wrong name only smears the ink.",
	"Kuro, the shikigami of the ledger, stays behind its holder. Nobody else can see or hear him.",
	"An ink that is still wet cannot be used again. Be patient.",
}

return LedgerData
