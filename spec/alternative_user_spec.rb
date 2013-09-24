require 'spec_helper'
require 'lacmus'

include Lacmus::Lab

describe Lacmus::AlternativeUser, 'AlternativeUser' do

  before do
    clear_cookies 
    Lacmus.restart_user_ids_counter
    Lacmus::Experiment.nuke_all_experiments
  end

  describe 'Basic functionality' do
    
    before do
      set_alternative_user_id(700)
    end

    it 'should modify the user id cookie' do
      expect(user_id_cookie[:value].split('|').last).to eq('1')
    end

    it 'should return the lacmus user id' do
      expect(Lacmus::AlternativeUser.get_user_id(700)).to eq('1')
    end

  end
end