require 'spec_helper'
require 'cocoapods-binary/Prebuild'


module Pod

    describe 'Prebuild' do
        describe 'Install' do

            before(:each) do
                SpecHelper.prebuild_installer_stubs(self)
                # data_flow = Prebuild::DataFlow.clone.instance
                # allow_any_instance_of(Prebuild::DataFlow).to receive(:instance) { data_flow }
            end

            describe 'Pod binarify strategy' do

                context 'when set some pod to binary' do
                    before(:each) do
                        SpecHelper.stub_pod_dependencies(self, { })
                        @installer, @sandbox, @podfile =  Pod.build_installer do
                            target 'A' do
                                pod "AFNetworking", :binary => true
                                pod "SnapKit"
                            end
                        end
                        @installer.install!
                    end

                    it "should have right pod target" do
                        @installer.pod_targets.map(&:name).should match_array(['AFNetworking'])
                    end
                    it "should have right binary pod" do
                        @installer.prebuild_pod_targets.map(&:name).should match_array(['AFNetworking'])
                    end
                end

                context 'when explicitly turn off a pod' do
                    before(:each) do
                        SpecHelper.stub_pod_dependencies(self, {
                            RxCocoa: ['RxSwift', '4.4.0'],
                            RxSwift: ['RxAtomic', '4.4.0'],
                        })
                        @installer, @sandbox, @podfile =  Pod.build_installer do
                            target 'A' do
                                pod "RxSwift", '4.4.0', :binary => false
                                pod "RxCocoa", '4.4.0', :binary => true
                                pod "SnapKit"
                            end
                        end
                        @installer.install!
                    end

                    it "should exclude the off in prebuild target" do
                        @installer.prebuild_pod_targets.map(&:name).should match_array(['RxAtomic', 'RxCocoa'])
                    end

                    it "should also have all dependencies in Pod project (for building)" do
                        @installer.pod_targets.map(&:name).should match_array(['RxAtomic', 'RxCocoa', 'RxSwift'])
                    end
                end

                context 'when binary pod have dependencies' do

                    context 'when implicit set dependencies' do
                        before(:each) do
                            SpecHelper.stub_pod_dependencies(self, {
                                RxCocoa: ['RxSwift', '4.4.0'],
                                RxSwift: ['RxAtomic', '4.4.0'],
                            })
                            @installer, @sandbox, @podfile =  Pod.build_installer do
                                target 'A' do
                                    pod "RxCocoa", '4.4.0', :binary => true
                                    pod "SnapKit"
                                end
                            end
                            @installer.install!
                        end

                        it "should have include all dependencies" do
                            [@installer.prebuild_pod_targets, @installer.pod_targets].each do |targets|
                                targets.map(&:name).should match_array(['RxAtomic', 'RxCocoa', 'RxSwift'])
                            end
                        end
                    end

                    context 'when explicitly set version for dependencies and make it non-binary' do
                        before(:each) do
                            SpecHelper.stub_pod_dependencies(self, {
                                RxCocoa: [['RxSwift', '>=4.4.0']],
                                RxSwift: ['RxAtomic', '4.4.0'],
                            })
                            @installer, @sandbox, @podfile =  Pod.build_installer do
                                target 'A' do
                                    pod "RxCocoa", '4.4.0', :binary => true
                                    pod "RxSwift", '4.5.0', :binary => false
                                    pod "SnapKit"
                                end
                            end
                            @installer.install!
                        end

                        it "should exclude the explicit off" do
                            @installer.prebuild_pod_targets.map(&:name).should match_array(['RxAtomic', 'RxCocoa'])
                        end

                        # doc_anchor
                        it "should have the right version for the explicit off" do
                            rxswift = @installer.pod_targets.find{ |t|t.pod_name == 'RxSwift'}
                            rxswift.should_not be_nil
                            spec = @installer.analysis_result.specifications.find{ |s|s.name == 'RxSwift'}
                            spec.version.to_s.should == '4.5.0'
                        end

                        it "should have all the dependencies to build in Pod project" do
                            @installer.pod_targets.map(&:name).should match_array(['RxAtomic', 'RxCocoa', 'RxSwift'])
                        end
                    end

                    context 'when explicitly set config for dependencies and make it non-binary(subspec)' do
                        before(:each) do
                            SpecHelper.stub_pod_dependencies(self, {
                                'SnapKit' => ['AFNetworking/Reachability', '>=3.1.0'],
                                'AFNetworking/Reachability' => [],
                            })
                            @installer, @sandbox, @podfile =  Pod.build_installer do
                                target 'A' do
                                    pod "SnapKit", :binary => true
                                    pod "AFNetworking/Reachability", '3.2.0', :binary => false
                                end
                            end
                            @installer.install!
                        end

                        it "should exclude the explicit off" do
                            @installer.prebuild_pod_targets.map(&:name).should match_array(['SnapKit'])
                        end

                        # doc_anchor
                        it "should have the right version for the explicit off" do
                            target = @installer.pod_targets.find{ |t|t.pod_name == 'AFNetworking'}
                            target.should_not be_nil
                            spec = @installer.analysis_result.specifications.find{ |s|s.name == 'AFNetworking/Reachability'}
                            spec.version.to_s.should == '3.2.0'
                        end

                        it "should have all the dependencies to build in Pod project" do
                            @installer.pod_targets.map(&:name).should match_array(['SnapKit', 'AFNetworking'])
                        end
                    end
                end

                context "When use multiple platforms" do
                    before(:each) do
                        SpecHelper.stub_pod_dependencies(self, { })
                        @installer, @sandbox, @podfile =  Pod.build_installer do
                            target 'A' do
                                platform :ios
                                pod "AFNetworking", :binary => true
                            end
                            target 'B' do
                                platform :watchos
                                pod "AFNetworking", :binary => false
                            end
                        end
                        @installer.install!
                    end

                    it "should have targets named with (pod_name + platform) " do
                        @installer.prebuild_pod_targets.map(&:name).should match_array(["AFNetworking-iOS", "AFNetworking-watchOS"])
                    end
                    it "for one pod, targets on different platforms should all be binary if one platform is binary" do
                        @installer.prebuild_pod_targets.map(&:pod_name).should match_array(["AFNetworking", "AFNetworking"])
                    end
                end

                context "When use subspecs" do
                    context 'when subspecs have different binary state' do
                        before(:each) do
                            SpecHelper.stub_pod_dependencies(self, { })
                            @installer, @sandbox, @podfile =  Pod.build_installer do
                                target 'A' do
                                    pod "AFNetworking/Reachability", :binary => true
                                    pod "AFNetworking/Security", :binary => false
                                    pod "SnapKit"
                                end
                            end
                            @installer.install!
                        end

                        it "should have target named with pod name " do
                            @installer.pod_targets.map(&:name).should match_array(['AFNetworking'])
                        end
                        it "should have all used subspec content (even a subspec is set to off explicitly)" do
                            target = @installer.pod_targets.first
                            target.specs.map(&:name).should match_array ['AFNetworking/Reachability', 'AFNetworking/Security']
                        end
                    end

                    context 'when use subspec in different targets' do
                        before(:each) do
                            SpecHelper.stub_pod_dependencies(self, { })
                            @installer, @sandbox, @podfile =  Pod.build_installer do
                                target 'A' do
                                    pod "AFNetworking/Security", :binary => true
                                end
                                target 'B' do
                                    pod "AFNetworking/Security", :binary => false # or true
                                end
                            end
                            @installer.install!
                        end

                        it "the binary target's name should equal to root pod name " do
                            @installer.prebuild_pod_targets.map(&:name).should match_array(['AFNetworking'])
                        end
                        it "should have just enough subspec content" do
                            target = @installer.prebuild_pod_targets.first
                            target.specs.map(&:name).should match_array ['AFNetworking/Security']
                        end
                    end

                    context 'when use different subspecs in different targets' do
                        before(:each) do
                            SpecHelper.stub_pod_dependencies(self, { })
                            @installer, @sandbox, @podfile =  Pod.build_installer do
                                target 'A' do
                                    pod "AFNetworking/Reachability", :binary => true
                                end
                                target 'B' do
                                    pod "AFNetworking/Security", :binary => false
                                end
                            end
                        end

                        #TODO
                        xit "should not be supported" do
                            # ["AFNetworking-Reachability", "AFNetworking-Security"]
                            expect {
                                @installer.install!
                            }.to raise_error
                        end
                    end

                    context 'when subspecs have dependency' do
                        before(:each) do
                            SpecHelper.stub_pod_dependencies(self, {
                                'AFNetworking/Security'.to_sym => ['Masonry', '1.1.0']
                            })
                            @installer, @sandbox, @podfile =  Pod.build_installer do
                                target 'A' do
                                    pod "AFNetworking/Security", :binary => true
                                end
                            end
                            @installer.install!
                        end

                        it "should have just enough content" do
                            target = @installer.prebuild_pod_targets.first
                            target.specs.map(&:name).should match_array ['AFNetworking/Security']
                            @installer.prebuild_pod_targets.map(&:name).should match_array(['AFNetworking', 'Masonry'])
                        end
                    end
                end

                context "when have local pod" do
                    before(:each) do
                        SpecHelper.stub_pod_dependencies(self, { })
                        allow_any_instance_of(Specification).to receive(:local?) { |s|
                            next true if s.name == 'AFNetworking' or s.name == 'SnapKit'
                            false
                        }
                        @installer, @sandbox, @podfile =  Pod.build_installer do
                            target 'A' do
                                pod "AFNetworking/Security", :binary => true # mock it to local
                                pod "SnapKit", :binary => true # mock it to local
                                pod "Literal", :binary => true
                            end
                        end
                        @installer.install!
                    end

                    it "local pod should be exclude" do
                        @installer.prebuild_pod_targets.map(&:name).should match_array(['Literal'])
                    end

                    it "local pod should still in project" do
                        @installer.pod_targets.map(&:name).should match_array(['AFNetworking', 'Literal', 'SnapKit'])
                    end

                end

            end


        end


    end

end
