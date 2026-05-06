-- 1. Update profiles table
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS skill_level INTEGER DEFAULT 5,
ADD COLUMN IF NOT EXISTS stamina_level INTEGER DEFAULT 5,
ADD COLUMN IF NOT EXISTS composite_score FLOAT DEFAULT 5.0;

-- 2. Update matches table
ALTER TABLE public.matches
ADD COLUMN IF NOT EXISTS intensity_level INTEGER DEFAULT 5,
ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'open'; -- 'open', 'in-progress', 'completed'

-- 3. Create match_reviews table
CREATE TABLE IF NOT EXISTS public.match_reviews (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    reviewer_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    reviewee_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    match_id UUID REFERENCES public.matches(id) ON DELETE CASCADE,
    skill_rating INTEGER CHECK (skill_rating >= 1 AND skill_rating <= 5),
    stamina_rating INTEGER CHECK (stamina_rating >= 1 AND stamina_rating <= 5),
    safety_rating INTEGER CHECK (safety_rating >= 1 AND safety_rating <= 5),
    sportsmanship_rating INTEGER CHECK (sportsmanship_rating >= 1 AND sportsmanship_rating <= 5),
    -- Ensure a user can only review another user once per match
    UNIQUE(reviewer_id, reviewee_id, match_id)
);

-- 4. Enable Row Level Security (RLS) for match_reviews
ALTER TABLE public.match_reviews ENABLE ROW LEVEL SECURITY;

-- 5. Create Policies for match_reviews
-- Anyone can read reviews
CREATE POLICY "Reviews are viewable by everyone" ON public.match_reviews
    FOR SELECT USING (true);

-- Authenticated users can insert reviews for others
CREATE POLICY "Authenticated users can create reviews" ON public.match_reviews
    FOR INSERT WITH CHECK (auth.uid() = reviewer_id);

-- 6. Trigger to automatically recalibrate composite_score on new review
CREATE OR REPLACE FUNCTION recalibrate_composite_score()
RETURNS TRIGGER AS $$
DECLARE
    avg_score NUMERIC;
BEGIN
    SELECT 
        AVG((skill_rating * 0.3) + (stamina_rating * 0.2) + (safety_rating * 0.3) + (sportsmanship_rating * 0.2))
    INTO avg_score
    FROM public.match_reviews
    WHERE reviewee_id = NEW.reviewee_id;

    UPDATE public.profiles
    SET composite_score = ROUND(avg_score, 2)
    WHERE id = NEW.reviewee_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_review_submitted ON public.match_reviews;
CREATE TRIGGER on_review_submitted
AFTER INSERT OR UPDATE ON public.match_reviews
FOR EACH ROW
EXECUTE FUNCTION recalibrate_composite_score();
